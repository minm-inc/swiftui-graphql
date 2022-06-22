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
public struct Query<Response: Queryable>: DynamicProperty {
    @EnvironmentObject public var client: GraphQLClient
    @StateObject var queryInternal = QueryOperation<Response>()
    
    public init(mergePolicy: MergePolicy? = nil) {
        prepopulatedResponse = nil
        self.mergePolicy = mergePolicy
    }
    public var wrappedValue: QueryOperation<Response> {
        get {
            if let prepopulatedResponse = prepopulatedResponse {
                let shim = QueryOperation<Response>()
                shim.prepopulatedResponse = prepopulatedResponse
                return shim
            }
            queryInternal.client = client
            queryInternal.mergePolicy = mergePolicy
            return queryInternal
        }
    }
    
    private let prepopulatedResponse: GraphQLResponse<Response>?
    private let mergePolicy: MergePolicy?
    
    public init(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.prepopulatedResponse = try decoder.decode(GraphQLResponse<Response>.self, from: data)
        self.mergePolicy = nil
    }
    
    public init(from prepopulatedResponse: GraphQLResponse<Response>) {
        self.prepopulatedResponse = prepopulatedResponse
        self.mergePolicy = nil
    }
}

public class QueryOperation<Response: Queryable>: Operation<Response> {
    
    fileprivate var prepopulatedResponse: GraphQLResponse<Response>?

    public func callAsFunction() -> State where Response.Variables == NoVariables {
        callAsFunction(NoVariables())
    }
    
    public func callAsFunction(_ variables: Response.Variables) -> State {
        switch prepopulatedResponse {
        case .data(let data):
            return .loaded(data: data)
        case .errors(_, let errors):
            return .error(GraphQLRequestError.graphqlError(errors))
        case nil:
            break
        }
        // Only make new request if variables have changed
        if (variables != self.variables) {
            self.variables = variables
            Task {
                do {
                    try await self.execute(variables: variables)
                } catch { }
            }
        }
        return state
    }
    
    public func refresh() async {
        guard let variables = self.variables else { return }
        do {
            try await self.execute(variables: variables)
        } catch { }
    }
}
