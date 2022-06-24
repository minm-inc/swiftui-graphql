//
//  Mutation.swift
//  Minm
//
//  Created by Luke Lau on 24/06/2021.
//

import Combine
import SwiftUI

@propertyWrapper
public struct Mutation<Response: Queryable>: DynamicProperty {
    // Note: Need the DynamicProperty protocol to get access to `@Environment`
    @Environment(\.graphqlClient) public var client: GraphQLClient
    @StateObject var operation = Operation<Response>()
    private let cacheUpdater: Cache.Updater?
    private let optimisticResponse: Response?

    public init(cacheUpdater: Cache.Updater? = nil, optimisticResponse: Response? = nil) {
        self.cacheUpdater = cacheUpdater
        self.optimisticResponse = optimisticResponse
    }
    
    public var wrappedValue: Operation<Response> {
        get {
            operation.client = client
            operation.cacheUpdater = cacheUpdater
            return operation
        }
    }
}

