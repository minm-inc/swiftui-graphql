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
// TODO: Introduce separate protocol for mutations
public struct Mutation<Response: Queryable & Encodable>: DynamicProperty {
    @EnvironmentObject public var client: GraphQLClient
    @StateObject var mutationInternal = MutationOperation<Response>()
    private let cacheUpdater: Cache.Updater?
    private let optimisticResponse: Response?

    public init(cacheUpdater: Cache.Updater? = nil, optimisticResponse: Response? = nil) {
        self.cacheUpdater = cacheUpdater
        self.optimisticResponse = optimisticResponse
    }
    
    public var wrappedValue: MutationOperation<Response> {
        get {
            mutationInternal.client = client
            mutationInternal.cacheUpdater = cacheUpdater
            return mutationInternal
        }
    }
}

public class MutationOperation<Response: Queryable & Encodable>: Operation<Response> {
    public var isLoading: Bool {
        switch state {
        case .loading: return true
        default: return false
        }
    }
    
    @discardableResult
    public func callAsFunction(_ variables: Response.Variables) async throws -> Response {
        try await execute(variables: variables)
    }
}

extension MutationOperation where Response.Variables == NoVariables {
    @discardableResult
    public func callAsFunction() async throws -> Response {
        try await callAsFunction(NoVariables())
    }
}
