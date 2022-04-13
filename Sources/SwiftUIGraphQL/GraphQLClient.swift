//
//  GraphQLClient.swift
//  
//
//  Created by Luke Lau on 24/06/2021.
//

import Foundation
import Combine

public class GraphQLClient: ObservableObject {
    var cache = Cache()
    
    let endpoint: URL
    let headerCallback: () -> [String: String]
    let urlSession: URLSession
    let scalarDecoder = FoundationScalarDecoder()
    
    public init(endpoint: URL, urlSession: URLSession = .shared, withHeaders headerCallback: @escaping () -> [String: String] = { [:]}) {
        self.endpoint = endpoint
        self.urlSession = urlSession
        self.headerCallback = headerCallback
    }
    
    func query(query: String, selection: ResolvedSelection<String>, variables: [ObjectKey: Value]?, cacheUpdater: Cache.Updater? = nil) async throws -> Value {
        let queryReq = QueryRequest(query: query, variables: variables)
        
        let data = try await makeRequestRaw(queryReq)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let graphqlResponse = try! decoder.decode(QueryResponse<Value>.self, from: data)
        if let errors = graphqlResponse.error {
            throw QueryError.errors(errors)
        }
        
        guard let decodedData = graphqlResponse.data else {
            throw QueryError.invalid
        }
        
        guard case let .object(decodedObj) = decodedData else {
            fatalError()
        }
        
        let selection = substituteVariables(in: selection, variableDefs: variables ?? [:])
        let (cacheObj, _) = await cache.mergeCache(incoming: decodedObj, selection: selection)
        await cacheUpdater?(cacheObj, cache)
        
        return decodedData
    }
    
    // Note: try! all the encoding/decoding as these are programming errors
    public func query<T: Queryable>(variables: T.Variables) async throws -> T {
        let decodedData = try await query(query: T.query, selection: T.selection, variables: variablesToObject(variables))
        return try! ValueDecoder(scalarDecoder: scalarDecoder).decode(T.self, from: decodedData)
    }
    
    func makeRequestRaw(_ queryRequest: QueryRequest) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (headerField, header) in headerCallback() {
            request.setValue(header, forHTTPHeaderField: headerField)
        }
        request.httpBody = try! JSONEncoder().encode(queryRequest)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            print(String(data: data, encoding: .utf8)!)
            throw QueryError.invalid
        }
        return data
    }

    public func makeRequest<T: Decodable>(_ queryRequest: QueryRequest) async throws -> T {
        let data = try await makeRequestRaw(queryRequest)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let graphqlResponse = try! decoder.decode(QueryResponse<T>.self, from: data)
        guard let decodedData = graphqlResponse.data else {
            throw QueryError.invalid
        }
        
        return decodedData
    }
}

public struct QueryResponse<T: Decodable>: Decodable {
    let data: T?
    let error: [GraphQLError]?
}

public struct GraphQLError: Decodable {
    let message: String
}

public struct QueryRequest: Encodable {
    let query: String
    let operationName: String?
    let variables: [ObjectKey: Value]?
    public init(query: String, operationName: String? = nil, variables: [ObjectKey: Value]? = nil) {
        self.query = query
        self.operationName = operationName
        self.variables = variables
    }
}

public enum QueryError: Error {
    case errors([GraphQLError])
    case invalid
}

func variablesToObject<Variables: Encodable>(_ variables: Variables) -> [ObjectKey: Value]? {
    let res: [ObjectKey: Value]?
    let variableValue: Value = try! ValueEncoder().encode(variables)
    switch variableValue {
    case .object(let obj):
        res = obj
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
    public init(fragment: Fragment, variableDefs: [ObjectKey: Value], client: GraphQLClient) {
        self.fragment = fragment
        cancellable = client.cache.publisher.sink { (changedKeys, store) in
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
