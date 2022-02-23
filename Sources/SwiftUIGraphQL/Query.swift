//
//  Query.swift
//  
//
//  Created by Luke Lau on 25/06/2021.
//

import Combine
import SwiftUI

/**
 Need the ``DynamicProperty`` protocol otherwise the `@Environment` variables aren't initialized yet
 */
@propertyWrapper
public struct Query<Query: Queryable>: DynamicProperty {
    @EnvironmentObject public var client: GraphQLClient
    @StateObject var queryInternal = QueryWatcher<Query>()
    public init() { prepopulatedResponse = nil }
    public var wrappedValue: QueryWatcher<Query> {
        get {
            if let prepopulatedResponse = prepopulatedResponse {
                let shim = QueryWatcher<Query>()
                shim.prepopulatedResponse = prepopulatedResponse
                return shim
            }
            queryInternal.client = client
            return queryInternal
        }
    }
    
    private let prepopulatedResponse: QueryResponse<Query>?
    
    public init(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.prepopulatedResponse = try decoder.decode(QueryResponse<Query>.self, from: data)
    }
    
    public init(from prepopulatedResponse: QueryResponse<Query>) {
        self.prepopulatedResponse = prepopulatedResponse
    }
}

//class CacheListener: ObservableObject {
//
//    private var cacheSink: AnyCancellable? = nil
//
//    func listen(to client: GraphQLClient) {
//        asyncDetached {
//        cacheSink = client.cachePublisher
//            .scan((nil, await client.getCache())) { ($0.1, $1) }
//            .map { old, new in
//                // TODO: Handle keys that have disappeared
//                new.filter { k, v in
//                    old?[k] != v
//                }
//            }.filter { !$0.isEmpty }
//            .sink { [weak self] newcache in
//                guard let self = self else { return }
//                asyncDetached {
//                    let cache = await client.getCache()
//                    switch self.state {
//                    case .loaded(let data):
//                        let value: Value = try! ValueEncoder().encode(data)
//                        let newData: Value = newcache.keys.reduce(value) { updateDataWithCache(data: $0, with: cache, newlyChangedKey: $1) }
//                        DispatchQueue.main.async {
//                            self.state = .loaded(data: try! ValueDecoder().decode(Query.self, from: newData))
//                        }
//                    default:
//                        break
//                    }
//                }
//            }
//        }
//    }
//}

public class QueryWatcher<Query: Queryable & Encodable>: ObservableObject {
    //    let client: GraphQLClient
    @Published public private(set) var state: State = .loading
    public enum State {
        case loading
        case loaded(data: Query)
        case error
    }
    
    private var cacheSink: AnyCancellable?
    
    private var variables: Query.Variables?
    
    fileprivate var prepopulatedResponse: QueryResponse<Query>?
    
    
    //    public init(_ type: Query.Type) {}
    //    public init() {}
    //    public convenience init(_ type: Query.Type) where Query.Variables == NoVariables {
    //        self.init(variables: NoVariables())
    //    }
    
    var client: GraphQLClient?
    
    public func run() -> State where Query.Variables == NoVariables {
        run(NoVariables())
    }
    
    public func run(_ variables: Query.Variables) -> State {
        if let prepopulatedQuery = prepopulatedResponse {
            if let data = prepopulatedQuery.data {
                return .loaded(data: data)
            } else {
                return .error
            }
        }
        guard let client = client else { fatalError("Client not set") }
        if cacheSink == nil {
            Task.detached {
                //        self.client = client
                self.cacheSink = client.cachePublisher
                    .scan((nil, await client.getCache())) { ($0.1, $1) }
                    .map { old, new in
                        // TODO: Handle keys that have disappeared
                        new.filter { k, v in
                            old?[k] != v
                        }
                    }.filter { !$0.isEmpty }
                    .sink { [weak self] newcache in
                        guard let self = self else { return }
                        Task.detached {
                            let cache = await client.getCache()
                            switch self.state {
                            case .loaded(let data):
                                let value: Value = try! ValueEncoder().encode(data)
                                let newValue = update(data: value, withChangedObjects: newcache.keys.reduce(into: [:]) { $0[$1] = cache[$1] })
                                let data = try! ValueDecoder().decode(Query.self, from: newValue)
                                DispatchQueue.main.async {
                                    self.state = .loaded(data: data)
                                }
                            default:
                                break
                            }
                        }
                    }
            }
        }
        if (variables != self.variables) {
            self.variables = variables
            Task.detached {
                do {
                    let data: Query = try await client.query(variables: variables)
                    DispatchQueue.main.async { self.state = .loaded(data: data) }
                } catch {
                    DispatchQueue.main.async { self.state = .error }
                }
            }
        }
        return state
    }
}

//public extension Query where Query.Variables == NoVariables {
//    init() {
//        self.init(variables: NoVariables())
//    }
//    //    func query() {
//    //        query(NoVariables())
//    //    }
//}

public enum TypenameCodingKeys: CodingKey {
    case __typename
}

public typealias ID = String
