//
//  GraphQLClient.swift
//  
//
//  Created by Luke Lau on 24/06/2021.
//

import Foundation
import Combine

public actor GraphQLClient: ObservableObject {
    var cache = Cache()
    
    let endpoint: URL
    let headerCallback: () -> [String: String]
    let urlSession: URLSession
    
    public init(endpoint: URL, urlSession: URLSession = .shared, withHeaders headerCallback: @escaping () -> [String: String] = { [:]}) {
        self.endpoint = endpoint
        self.urlSession = urlSession
        self.headerCallback = headerCallback
    }
    
    func query(query: String, selections: [ResolvedSelection<String>], variables: [String: Value]?) async throws -> Value {
        let queryReq = QueryRequest(query: query, variables: variables)
        
        let data = try await makeRequestRaw(queryReq)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let graphqlResponse = try! decoder.decode(QueryResponse<Value>.self, from: data)
        if let error = graphqlResponse.error {
            throw QueryError.invalid
        }
        
        guard let decodedData = graphqlResponse.data else {
            throw QueryError.invalid
        }
        
        guard case let .object(decodedObj) = decodedData else {
            fatalError()
        }
        
        let selections = substituteVariables(in: selections, variableDefs: variables ?? [:])
        let cacheObject = cacheObject(from: decodedObj, selections: selections)
        // cacheobject doesn't contain inLibrary???
        await cache.mergeCache(incoming: cacheObject)
        
        return decodedData
    }
    
    // Note: try! all the encoding/decoding as these are programming errors
    public func query<T: Queryable>(variables: T.Variables) async throws -> T {
        let decodedData = try await query(query: T.query, selections: T.selections, variables: variablesToDict(variables))
        return try! ValueDecoder().decode(T.self, from: decodedData)
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
    let variables: [String: Value]?
    public init(query: String, operationName: String? = nil, variables: [String: Value]? = nil) {
        self.query = query
        self.operationName = operationName
        self.variables = variables
    }
}

enum QueryError: Error {
    case invalid
}



func variablesToDict<Variables: Encodable>(_ variables: Variables) -> [String: Value]? {
    let res: [String: Value]?
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
