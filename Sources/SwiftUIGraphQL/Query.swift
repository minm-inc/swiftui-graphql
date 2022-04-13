//
//  File.swift
//  
//
//  Created by Luke Lau on 04/04/2022.
//

import Foundation

import SwiftUI

/**
 Need the ``DynamicProperty`` protocol otherwise the `@Environment` variables aren't initialized yet
 */
@propertyWrapper
public struct Query<Query: Queryable>: DynamicProperty {
    @EnvironmentObject public var client: GraphQLClient
    @StateObject var queryInternal = QueryOperation<Query>()
    
    public init(mergePolicy: MergePolicy? = nil) {
        prepopulatedResponse = nil
        self.mergePolicy = mergePolicy
    }
    public var wrappedValue: QueryOperation<Query> {
        get {
            if let prepopulatedResponse = prepopulatedResponse {
                let shim = QueryOperation<Query>()
                shim.prepopulatedResponse = prepopulatedResponse
                return shim
            }
            queryInternal.client = client
            queryInternal.mergePolicy = mergePolicy
            return queryInternal
        }
    }
    
    private let prepopulatedResponse: QueryResponse<Query>?
    private let mergePolicy: MergePolicy?
    
    public init(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.prepopulatedResponse = try decoder.decode(QueryResponse<Query>.self, from: data)
        self.mergePolicy = nil
    }
    
    public init(from prepopulatedResponse: QueryResponse<Query>) {
        self.prepopulatedResponse = prepopulatedResponse
        self.mergePolicy = nil
    }
}

public class QueryOperation<Response: Queryable>: Operation<Response> {
    
    fileprivate var prepopulatedResponse: QueryResponse<Response>?

    public func callAsFunction() -> State where Response.Variables == NoVariables {
        callAsFunction(NoVariables())
    }
    
    public func callAsFunction(_ variables: Response.Variables) -> State {
        if let prepopulatedQuery = prepopulatedResponse {
            if let data = prepopulatedQuery.data {
                return .loaded(data: data)
            } else {
                return .error(.invalid)
            }
        }
        // Only make new request if variables have changed
        if (variables != self.variables) {
            self.variables = variables
            Task {
                do {
                    let _ = try await self.execute(variables: variables)
                } catch {
                    // TODO handle network errors
//                    if let error = error as? QueryError {
//                        self.state = .error(error)
//                    } else {
//                        self.state = .error(.invalid)
//                    }
                }
            }
        }
        return state
    }
}
