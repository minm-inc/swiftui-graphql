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
    private let cacheUpdate: ((NormalizedCacheValue, Cache) async -> Void)?

    public init(cacheUpdate: ((NormalizedCacheValue, Cache) async -> Void)? = nil) {
        self.cacheUpdate = cacheUpdate
    }
    
    public var wrappedValue: MutationWatcher<Mutation> {
        get {
            mutationInternal.client = client
            mutationInternal.cacheUpdate = cacheUpdate
            return mutationInternal
        }
    }
}

public class MutationWatcher<Mutation1: Queryable & Encodable>: Operation<Mutation1> {    
    public var isLoading: Bool {
        switch state {
        case .loading: return true
        default: return false
        }
    }
    
    @discardableResult
    public func callAsFunction(_ variables: Mutation1.Variables) async throws -> Mutation1 {
        let response = try await execute(variables: variables)
        return try! ValueDecoder().decode(Mutation1.self, from: response.value)
    }
}

extension MutationWatcher where Mutation1.Variables == NoVariables {
    @discardableResult
    public func callAsFunction() async throws -> Mutation1 {
        try await callAsFunction(NoVariables())
    }
}
