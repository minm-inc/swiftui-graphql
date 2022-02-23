//
//  Mutation.swift
//  Minm
//
//  Created by Luke Lau on 24/06/2021.
//

import Combine
import SwiftUI

/**
 Need the ``DynamicProperty`` protocol otherwise the `@Environment` variables aren't initialized yet
 */
@propertyWrapper
public struct Mutation<Mutation: Queryable & Encodable>: DynamicProperty {
    @EnvironmentObject public var client: GraphQLClient
    @StateObject var mutationInternal = MutationWatcher<Mutation>()

    public init() {}
    
    public var wrappedValue: MutationWatcher<Mutation> {
        get {
            mutationInternal.graphqlClient = client
            return mutationInternal
        }
    }
}

public class MutationWatcher<Mutation1: Queryable & Encodable>: ObservableObject {
    var graphqlClient: GraphQLClient!
    
    public enum State {
        case notCalled
        case loading
        case loaded(data: Mutation1)
        case error
    }
    /**
     The state of the mutation's execution. `nil`
     */
    @Published public private(set) var state: State = .notCalled
    
    public var isLoading: Bool {
        switch state {
        case .loading: return true
        default: return false
        }
    }
    
    public init() { }
    
    private var cacheCancellable: AnyCancellable? = nil
    
    @discardableResult
    public func execute(variables: Mutation1.Variables) async throws -> Mutation1 {
        self.cacheCancellable = self.graphqlClient.cachePublisher
            .scan((nil, await self.graphqlClient.getCache())) { ($0.1, $1) }
            .map { old, new in
                // TODO: Handle keys that have disappeared
                new.filter { k, v in
                    old?[k] != v
                }
            }.filter { !$0.isEmpty }
            .sink { [weak self] newcache in
                guard let self = self else { return }
                Task.detached {
                    let cache = await self.graphqlClient.getCache()
                    switch self.state {
                    case .loaded(let data):
                        let value: Value = try! ValueEncoder().encode(data)
                        let newValue = update(data: value, withChangedObjects: newcache.keys.reduce(into: [:]) { $0[$1] = cache[$1] })
                        let data = try! ValueDecoder().decode(Mutation1.self, from: newValue)
                        DispatchQueue.main.async {
                            self.state = .loaded(data: data)
                        }
                    default:
                        break
                    }
                }
            }
        
        do {
            let data: Mutation1 = try await self.graphqlClient.query(variables: variables)
            DispatchQueue.main.async { self.state = .loaded(data: data) }
            return data
        } catch {
            print(error)
            DispatchQueue.main.async { self.state = .error }
            throw error
        }
    }
}

extension MutationWatcher where Mutation1.Variables == NoVariables {
    func execute() async throws -> Mutation1 {
        return try await execute(variables: NoVariables())
    }
}
