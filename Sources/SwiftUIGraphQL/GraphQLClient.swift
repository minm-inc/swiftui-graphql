//
//  GraphQLClient.swift
//  
//
//  Created by Luke Lau on 24/06/2021.
//

import Foundation
import Combine
import SwiftUI

public class GraphQLClient: ObservableObject {
    public let cache = Cache()

    let transport: any Transport
    let scalarDecoder: any ScalarDecoder
    let errorCallback: (@MainActor (any Error) -> Bool)?

    /// A convenience method for creating a client with a ``HTTPTransport``
    public convenience init(endpoint: URL) {
        self.init(transport: HTTPTransport(endpoint: endpoint))
    }

    public init(transport: any Transport,
                onError errorCallback: (@MainActor (any Error) -> Bool)? = nil,
                scalarDecoder: ScalarDecoder = FoundationScalarDecoder()) {
        self.transport = transport
        self.errorCallback = errorCallback
        self.scalarDecoder = scalarDecoder
    }

    public enum CachePolicy : Sendable{
        case cacheFirstElseNetwork
        case cacheFirstThenNetwork
        case networkOnly
    }

    public struct QueryWatcher<Element>: AsyncSequence {
        typealias CacheListener = AsyncMapSequence<AsyncStream<[ObjectKey : Value]?>, Element?>
        let makeCacheListener: @Sendable () async -> CacheListener
        typealias Resolver = @Sendable () async throws -> Element?
        let cacheResolver: Resolver
        let networkResolver: Resolver
        let cachePolicy: CachePolicy


        public func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(makeCacheListener: makeCacheListener,
                          cacheResolver: cacheResolver,
                          networkResolver: networkResolver,
                          cachePolicy: cachePolicy)
        }

        public struct AsyncIterator: AsyncIteratorProtocol {
            internal init(makeCacheListener: @escaping @Sendable () async -> CacheListener,
                          cacheResolver: @escaping Resolver,
                          networkResolver: @escaping Resolver,
                          cachePolicy: GraphQLClient.CachePolicy) {
                self.makeCacheListener = makeCacheListener
                self.cacheResolver = cacheResolver
                self.networkResolver = networkResolver
                self.cachePolicy = cachePolicy
            }

            let makeCacheListener: @Sendable () async -> CacheListener
            let cacheResolver: Resolver
            let networkResolver: Resolver
            let cachePolicy: CachePolicy

            private var cacheIterator: CacheListener.AsyncIterator?
            private var triedCache = false
            private var triedNetwork = false

            public mutating func next() async throws -> Element? {
                if Task.isCancelled { return nil }

                switch cachePolicy {
                case .cacheFirstElseNetwork:
                    if !triedCache {
                        triedCache = true
                        if let cacheHit = try await cacheResolver() {
                            return cacheHit
                        } else {
                            return try await networkResolver()
                        }
                    } else {
                        return try await changesResolver()
                    }
                case .cacheFirstThenNetwork:
                    if !triedCache {
                        triedCache = true
                        return try await cacheResolver()
                    } else if !triedNetwork {
                        triedNetwork = true
                        return try await networkResolver()
                    } else {
                        return try await changesResolver()
                    }
                case .networkOnly:
                    if !triedNetwork {
                        triedNetwork = true
                        return try await networkResolver()
                    } else {
                        return try await changesResolver()
                    }
                }
            }

            private mutating func changesResolver() async throws -> Element? {
                if cacheIterator == nil {
                    cacheIterator = await makeCacheListener().makeAsyncIterator()
                }
                let next = await cacheIterator!.next()
                switch next {
                case .none:
                    // The listener finished
                    return nil
                case .some(.none):
                    // The cache was invalidated: fetch from network
                    return try await networkResolver()
                case .some(.some(let next)):
                    // The cache was updated
                    return next
                }
            }
        }
    }

    func watchValue<T: Operation>(_ operation: T.Type,
                                  variables: T.Variables,
                                  cachePolicy: CachePolicy,
                                  cacheUpdater: Cache.Updater?) async -> QueryWatcher<Value> {

        let resolvedSelection = substituteVariables(in: T.selection, variableDefs: variablesToObject(variables))

        let cacheResolver = { @Sendable in
            await self.cache.value(from: self.cache.store[.queryRoot]!, selection: resolvedSelection).map { Value.object($0) }
        }
        let networkResolver = { @Sendable () -> Value in
            try await self.execute(operation, variables: variables, cacheUpdater: cacheUpdater)
        }
        let makeCacheListener = { @Sendable in
            await self.cache.listenToChanges(selection: resolvedSelection, on: .queryRoot).map { $0.map { Value.object($0) } }
        }

        return QueryWatcher<Value>(makeCacheListener: makeCacheListener,
                                   cacheResolver: cacheResolver,
                                   networkResolver: networkResolver,
                                   cachePolicy: cachePolicy)
    }

    public func watch<T: Operation>(_ operation: T.Type,
                                    variables: T.Variables,
                                    cachePolicy: CachePolicy = .cacheFirstElseNetwork,
                                    cacheUpdater: Cache.Updater? = nil) async -> AsyncMapSequence<QueryWatcher<Value>, T> {
        await watchValue(operation, variables: variables, cachePolicy: cachePolicy, cacheUpdater: cacheUpdater).map {
            try! ValueDecoder(scalarDecoder: self.scalarDecoder).decode(T.self, from: $0)
        }
    }

    public func watch<T: Operation>(_ operation: T.Type,
                                    cachePolicy: CachePolicy = .cacheFirstElseNetwork,
                                    cacheUpdater: Cache.Updater? = nil) async -> AsyncMapSequence<QueryWatcher<Value>, T> where T.Variables == NoVariables {
        await watch(operation, variables: NoVariables(), cachePolicy: cachePolicy, cacheUpdater: cacheUpdater)
    }
    
    // TODO: Make the API surface nicer: potentially generate the selection from just the query string, or only take in selection + variables
    /// All requests to the server within a ``GraphQLClient`` should go through here, where it takes care of updating the cache and stuff.
    private func execute<T: Operation>(_ operation: T.Type, variables: T.Variables, cacheUpdater: Cache.Updater?) async throws -> Value {
        let variablesDict = variablesToObject(variables)
        do {
            let response = try await makeTransportRequest(operation, variables: variablesDict)
            guard case .data(.object(let incoming)) = response else {
                throw GraphQLRequestError.invalidGraphQLResponse
            }
            
            let selection = substituteVariables(in: T.selection, variableDefs: variablesDict)
            if isMutationOperationType(T.self) {
                await cache.mergeMutation(incoming, selection: selection, updater: cacheUpdater)
            } else {
                await cache.mergeQuery(incoming, selection: selection, updater: cacheUpdater)
            }
            
            return .object(incoming)
        } catch {
            let shouldRetry = await MainActor.run {
                errorCallback?(error) ?? false
            }
            if shouldRetry {
                return try await self.execute(operation, variables: variables, cacheUpdater: cacheUpdater)
            } else {
                throw error
            }
        }
    }

    /// Exists so we can override it within ``MockGraphQLClient``
    func makeTransportRequest<T: Operation>(_ operation: T.Type, variables: [String: Value]?) async throws -> GraphQLResponse<Value> {
        try await transport.makeRequest(query: T.query,
                                        variables: variables,
                                        response: Value.self)
    }

    public func execute<T: Operation>(_ operation: T.Type, variables: T.Variables, cacheUpdater: Cache.Updater? = nil) async throws -> T {
        let decodedData: Value = try await execute(operation, variables: variables, cacheUpdater: cacheUpdater)
        // Use a try! here because failing to decode an Operation from a Value is a programming error
        return try! ValueDecoder(scalarDecoder: scalarDecoder).decode(T.self, from: decodedData)
    }

    public func execute<T: Operation>(_ operation: T.Type, cacheUpdater: Cache.Updater? = nil) async throws -> T where T.Variables == NoVariables {
        return try await execute(operation, variables: NoVariables(), cacheUpdater: cacheUpdater)
    }
}


func variablesToObject<Variables: Encodable>(_ variables: Variables) -> [String: Value]? {
    let res: [String: Value]?
    let variableValue: Value = try! ValueEncoder().encode(variables)
    switch variableValue {
    case .object(let obj):
        res = ObjectKey.convert(object: obj)
    case .null:
        res = nil
    default:
        fatalError("Invalid variables type")
    }
    return res
}

private class PlaceholderGraphQLClient: GraphQLClient {
    struct PlaceholderTransport: Transport {
        func makeRequest<T: Decodable>(query: String, variables: [String : Value]?, response: T.Type) async throws -> GraphQLResponse<T> {
            fatalError("You need to set \\.graphqlClient somewhere in the environment hierarchy!")
        }
    }
    init() { super.init(transport: PlaceholderTransport()) }
}

struct GraphQLClientKey: EnvironmentKey {
    static var defaultValue: GraphQLClient = PlaceholderGraphQLClient()
}

public extension EnvironmentValues {
    var graphqlClient: GraphQLClient {
        get { self[GraphQLClientKey.self] }
        set { self[GraphQLClientKey.self] = newValue }
    }
}

public enum GraphQLRequestError: Error {
    /// There were errors returned in the GraphQL response
    case graphqlError([GraphQLError])
    /// The server returned a badly-formed response
    case invalidGraphQLResponse
}

func isMutationOperationType(_ type: (some Operation).Type) -> Bool {
    type.self is any MutationOperation.Type
}


extension GraphQLClient.QueryWatcher: Sendable where Element: Sendable {}
