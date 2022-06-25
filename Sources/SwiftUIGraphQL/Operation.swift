//
//  Query.swift
//  
//
//  Created by Luke Lau on 25/06/2021.
//

import Combine
import Foundation


/// Watches the cache for any changes to the cache and updates its response
@MainActor
public class Operation<Response: Queryable>: ObservableObject {
    private var response: Value? = nil {
        didSet {
            // Don't publish unecessary updates if nothing changed
            if response == oldValue {
                return
            }
            if let response {
                result.data = try! ValueDecoder(scalarDecoder: client!.scalarDecoder).decode(Response.self, from: response)
            } else {
                result.data = nil
            }
        }
    }

    @Published public private(set) var result = GraphQLResult<Response>(data: nil, isFetching: true, error: nil)

    private var variables: Response.Variables?
    
    private var cacheSink: AnyCancellable?
    
    var client: GraphQLClient? {
        didSet {
            guard let client else {
                self.cacheSink?.cancel()
                self.cacheSink = nil
                return
            }
            if oldValue === client { return }
            self.cacheSink = client.cache.publisher
                .receive(on: DispatchQueue.main)
                .sink { [unowned self] (changedKeys, cacheStore) in
                    guard let response = self.response else {
                        return
                    }
                    // TODO: self.variables here smells like a race condition
                    let selection = substituteVariables(in: Response.selection, variableDefs: variablesToObject(self.variables) ?? [:])
                    self.response = update(value: response, selection: selection, changedKeys: changedKeys, cacheStore: cacheStore)
                }
        }
    }

    var mergePolicy: MergePolicy? = nil
    var cacheUpdater: Cache.Updater? = nil
    
    @MainActor
    @discardableResult
    func execute(variables: Response.Variables) async throws -> Response {
        guard let client = client else { fatalError("Client not set") }
        self.variables = variables
        
        let variablesObj = variablesToObject(variables)
        var incoming: Value
        do {
            result.isFetching = true
            incoming = try await client.query(query: Response.query, selection: Response.selection, variables: variablesObj, cacheUpdater: cacheUpdater)
            result.isFetching = false
            if let mergePolicy {
                incoming = mergePolicy.merge(existing: response, incoming: incoming)
            }
            self.response = incoming
            result.error = nil
        } catch {
            result.error = error
            result.isFetching = false
            throw error
        }
        return try! ValueDecoder(scalarDecoder: client.scalarDecoder).decode(Response.self, from: incoming)
    }
    
    @discardableResult
    public func callAsFunction(_ variables: Response.Variables) async throws -> Response {
        try await execute(variables: variables)
    }
    
    @discardableResult
    public func callAsFunction() async throws -> Response where Response.Variables == NoVariables {
        try await callAsFunction(NoVariables())
    }
}

/// The result of a GraphQL operation.
public struct GraphQLResult<Response> {
    /// The data returned by the server for your operation.
    public internal(set) var data: Response?
    /// Whether or not the operation is currently being fetched/loading.
    public internal(set) var isFetching: Bool
    /// Any errors that occurred during the previous request.
    ///
    /// There are three main types of errors you want to catch:
    /// 1. GraphQL errors, i.e. errors that ocurred whilst executing your operation on the server, which are returned in the form of ``GraphQLRequestError/graphqlError(_:)``
    /// 2. Network errors that come from URLSession itself, i.e. there's no Internet connection etc. These are usually URLErrors
    /// 3. HTTP errors that came from a non-2xx status code, which will be in the form of ``GraphQLRequestError/invalidHTTPResponse(_:)``
    ///
    /// ```swift
    /// switch query {
    /// case .loading: ProgressView()
    /// case .loaded(let data): MyView(data)
    /// case .error(is URLError): Text("A network error ocurred")
    /// case .error: Text("An unknown error ocurred")
    /// }
    /// ```
    public internal(set) var error: (any Error)?
}


public struct MergePolicy: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (ObjectKey, MergePolicy)...) {
        self.fields = Dictionary(uniqueKeysWithValues: elements)
        self.f = nil
    }
    
    public init(_ f: @escaping (SwiftUIGraphQL.Value, SwiftUIGraphQL.Value) -> SwiftUIGraphQL.Value) {
        self.f = f
        self.fields = [:]
    }
    
    static let `default`: MergePolicy = [:]
    
    let f: ((SwiftUIGraphQL.Value, SwiftUIGraphQL.Value) -> SwiftUIGraphQL.Value)?
    let fields: [ObjectKey: MergePolicy]
    
    func merge(existing: SwiftUIGraphQL.Value?, incoming: SwiftUIGraphQL.Value) -> SwiftUIGraphQL.Value {
        guard let existing else {
            return incoming
        }
        var res = incoming
        switch (existing, res) {
        case (.object(let existingObj), .object(var incomingObj)):
            for (key, incomingVal) in incomingObj {
                if let policy = fields[key], let existingVal = existingObj[key] {
                    incomingObj[key] = policy.merge(existing: existingVal, incoming: incomingVal)
                }
            }
            res = .object(incomingObj)
        default:
            break
        }
        if let f = f {
            res = f(existing, res)
        }
        return res
    }
}

