//
//  Operation.swift
//  
//
//  Created by Luke Lau on 25/06/2021.
//

import Combine
import Foundation

/// Watches the cache for any changes to the cache and updates its response
@MainActor
public class OperationWatcher<Response: Operation>: ObservableObject {
    @Published public private(set) var result = GraphQLResult<Response>(data: nil, isFetching: true, error: nil)
    private var currentValue: Value?

    private var listenTask: Task<Void, Never>?
    var cachePolicy: GraphQLClient.CachePolicy?
    var cacheUpdater: Cache.Updater?
    var client: GraphQLClient!

    @MainActor
    @discardableResult
    func execute(variables: Response.Variables, mergePolicy: MergePolicy? = nil) async throws -> Response {
        listenTask?.cancel()

        var iterator = await client.watch(query: Response.query,
                                          selection: Response.selection,
                                          variables: variablesToObject(variables),
                                          isMutation: isMutationOperationType(Response.self),
                                          cachePolicy: cachePolicy ?? .cacheFirstElseNetwork,
                                          cacheUpdater: cacheUpdater).makeAsyncIterator()

        @discardableResult
        func receivedIncoming(_ value: Value) -> Response {
            var value = value
            if let mergePolicy {
                value = mergePolicy.merge(existing: currentValue, incoming: value)
            }
            let decodedResponse = try! ValueDecoder(scalarDecoder: client.scalarDecoder).decode(Response.self, from: value)
            result = GraphQLResult(data: decodedResponse, isFetching: false, error: nil)

            currentValue = value

            return decodedResponse
        }

        do {
            result.isFetching = true
            let initialResponse = receivedIncoming(try await iterator.next()!)

            listenTask = Task {
                do {
                    while let incoming = try await iterator.next() {
                        receivedIncoming(incoming)
                    }
                } catch {
                    result = GraphQLResult(data: result.data, isFetching: false, error: error)
                }
            }

            return initialResponse
        } catch {
            result = GraphQLResult(data: result.data, isFetching: false, error: error)
            throw error
        }
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
