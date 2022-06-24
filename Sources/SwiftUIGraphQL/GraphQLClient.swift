//
//  GraphQLClient.swift
//  
//
//  Created by Luke Lau on 24/06/2021.
//

import Foundation
import Combine

public final class GraphQLClient: ObservableObject {
    let cache = Cache()
    
    let endpoint: URL
    let headerCallback: () -> [String: String]
    let urlSession: URLSession
    let scalarDecoder: any ScalarDecoder
    let errorCallback: (@MainActor (any Error) -> Bool)?
    
    public init(endpoint: URL,
                urlSession: URLSession = .shared,
                withHeaders headerCallback: @escaping () -> [String: String] = { [:] },
                onError errorCallback: (@MainActor (any Error) -> Bool)? = nil,
                scalarDecoder: ScalarDecoder = FoundationScalarDecoder()) {
        self.endpoint = endpoint
        self.urlSession = urlSession
        self.headerCallback = headerCallback
        self.errorCallback = errorCallback
        self.scalarDecoder = scalarDecoder
    }
    
    /// All requests to the server within a ``GraphQLClient`` should go through here, where it takes care of updating the cache and stuff.
    func query(query: String, selection: ResolvedSelection<String>, variables: [String: Value]?, cacheUpdater: Cache.Updater? = nil) async throws -> Value {
        let queryReq = GraphQLRequest(query: query, variables: variables)
        
        do {
            guard case .object(let incoming) = try await makeRequest(queryReq,
                                                                     response: Value.self,
                                                                     endpoint: endpoint,
                                                                     urlSession: urlSession,
                                                                     headers: headerCallback()) else {
                throw GraphQLRequestError.invalidGraphQLResponse
            }
            
            let selection = substituteVariables(in: selection, variableDefs: variables ?? [:])
            await cache.mergeCache(incoming: incoming, selection: selection, updater: cacheUpdater)
            
            return .object(incoming)
        } catch {
            let shouldRetry = await MainActor.run {
                errorCallback?(error) ?? false
            }
            if shouldRetry {
                return try await self.query(query: query,
                                            selection: selection,
                                            variables: variables,
                                            cacheUpdater: cacheUpdater)
            } else {
                throw error
            }
        }
    }
    
    
    public func query<T: Queryable>(_ queryable: T.Type, variables: T.Variables) async throws -> T {
        let decodedData = try await query(query: T.query, selection: T.selection, variables: variablesToObject(variables))
        // Use a try! here because failing to decode a Queryable from a Value is a programming error
        return try! ValueDecoder(scalarDecoder: scalarDecoder).decode(T.self, from: decodedData)
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


public class CacheTracked<Fragment: Cacheable>: ObservableObject {
    @Published public private(set) var fragment: Fragment
    private var cancellable: AnyCancellable? = nil
    public init(fragment: Fragment, variableDefs: [String: Value], client: GraphQLClient) {
        self.fragment = fragment
        cancellable = client.cache.publisher.receive(on: RunLoop.main).sink { (changedKeys, store) in
            let cacheKey = CacheKey(type: fragment.__typename, id: fragment.id)
            let cacheObject = store[cacheKey]!
            let selection = substituteVariables(in: Fragment.selection, variableDefs: variableDefs)
            let value = value(from: .object(cacheObject), selection: selection, cacheStore: store)
            self.fragment = try! ValueDecoder(scalarDecoder: client.scalarDecoder).decode(Fragment.self, from: value)
        }
    }
    
    /// Initializes a static fragment definition. Useful for in testing.
    public init(fragment: Fragment) {
        self.fragment = fragment
    }
}
