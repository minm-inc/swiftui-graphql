//
//  File.swift
//  
//
//  Created by Luke Lau on 04/04/2022.
//

import Foundation
import Combine
import SwiftUI

@propertyWrapper
public struct Query<Response: QueryOperation>: DynamicProperty {
    // Need DynamicProperty in order to access the environment
    @Environment(\.graphqlClient) public var client: GraphQLClient
    @StateObject private var request = Request()
    
    @MainActor
    public class Request: ObservableObject {
        fileprivate var mergePolicy: MergePolicy?
        fileprivate let operation = OperationWatcher<Response>()
        private var needsRefetch = true
        fileprivate var _variables: Response.Variables! {
            didSet {
                if oldValue != _variables {
                    needsRefetch = true
                    executeIfNeeded()
                }
            }
        }
        public var variables: Response.Variables {
            get { _variables }
            set { _variables = newValue }
        }
        private var cancellable: AnyCancellable?
        fileprivate init() {
            cancellable = operation.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
        
        fileprivate func executeIfNeeded() {
            if needsRefetch {
                Task { await execute() }
            }
            needsRefetch = false
        }
        
        public func execute(variables: Response.Variables, mergePolicy: MergePolicy?) async {
            do { try await operation.execute(variables: variables, mergePolicy: mergePolicy) }
            catch {}
        }

        public func execute() async {
            await execute(variables: self.variables, mergePolicy: self.mergePolicy)
        }
    }
    
    private let variables: Response.Variables
    private let mergePolicy: MergePolicy?
    private let cachePolicy: GraphQLClient.CachePolicy
    
    public init(variables: Response.Variables, cachePolicy: GraphQLClient.CachePolicy = .cacheFirstElseNetwork, mergePolicy: MergePolicy? = nil) {
        self.variables = variables
        self.mergePolicy = mergePolicy
        self.cachePolicy = cachePolicy
    }
    
    // Note: We'd love to add a default value of nil for mergePolicy, but there is a bug
    // that prevents us from manually instantiating the property wrapper:
    // https://github.com/apple/swift/issues/55019
    public init(cachePolicy: GraphQLClient.CachePolicy = .cacheFirstElseNetwork, mergePolicy: MergePolicy?) where Response.Variables == NoVariables {
        self.init(variables: NoVariables(), cachePolicy: cachePolicy, mergePolicy: mergePolicy)
    }

    public var wrappedValue: GraphQLResult<Response> {
        request.operation.result
    }
    
    public var projectedValue: Request {
        request
    }
    
    public func update() {
        request._variables = variables
        request.operation.client = client
        request.operation.cachePolicy = cachePolicy
        request.mergePolicy = mergePolicy
        request.executeIfNeeded()
    }
}
