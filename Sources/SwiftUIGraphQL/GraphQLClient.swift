//
//  GraphQLClient.swift
//  
//
//  Created by Luke Lau on 24/06/2021.
//

import Foundation
import Combine

public struct NoVariables: Encodable, Equatable {
    public init() {}
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encodeNil()
    }
}

public protocol Cacheable: Codable, Identifiable {
    var __typename: String { get }
    var id: String { get }
}

public protocol Queryable: Codable {
    static var query: String { get }
    associatedtype Variables = NoVariables where Variables: Encodable & Equatable
}

public actor GraphQLClient: ObservableObject {
    private var cache = Cache()
    let cachePublisher = PassthroughSubject<[CacheKey: CacheObject], Never>()
    
    let apiUrl: URL
    let headerCallback: () -> [String: String]
    
    public init(url: URL, withHeaders headerCallback: @escaping () -> [String: String]) {
        self.apiUrl = url
        self.headerCallback = headerCallback
    }
    
    // Note: try! all the encoding/decoding as these are programming errors
    public func query<T: Queryable>(variables: T.Variables) async throws -> T {
        let variablesDict: [String: Value]?
        let variableValue: Value = try! ValueEncoder().encode(variables)
        switch variableValue {
        case .object(let obj):
            variablesDict = obj
        case .null:
            variablesDict = nil
        default:
            fatalError("Invalid variables type")
        }
        
        let queryReq = QueryRequest(query: T.query, variables: variablesDict)
        
        let data = try await makeRequestRaw(queryReq, endpoint: apiUrl, headers: headerCallback())
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let graphqlResponse = try! decoder.decode(QueryResponse<T>.self, from: data)
        
        if let error = graphqlResponse.error {
            throw QueryError.invalid
        }
        
        guard let decodedData = graphqlResponse.data else {
            throw QueryError.invalid
        }
        
        let looseData = try! decoder.decode(Value.self, from: data)
        cache.mergeCache(incoming: looseData)
        cachePublisher.send(cache.store)
        
        return decodedData
    }
    
    func getCache() -> [CacheKey: CacheObject] {
        return cache.store
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

func makeRequestRaw(_ queryRequest: QueryRequest, endpoint: URL, headers: [String: String] = [:]) async throws -> Data {
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    for (headerField, header) in headers {
        request.setValue(header, forHTTPHeaderField: headerField)
    }
    request.httpBody = try! JSONEncoder().encode(queryRequest)
    
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        print(String(data: data, encoding: .utf8)!)
        throw QueryError.invalid
    }
    return data
}

public func makeRequest<T: Decodable>(_ queryRequest: QueryRequest, endpoint: URL) async throws -> T {
    let data = try await makeRequestRaw(queryRequest, endpoint: endpoint)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let graphqlResponse = try! decoder.decode(QueryResponse<T>.self, from: data)
    guard let decodedData = graphqlResponse.data else {
        throw QueryError.invalid
    }
    
    return decodedData
}

func update(data: Value, withChangedObjects changedObjects: [CacheKey: CacheObject?]) -> Value {
    switch data {
    case .object(let obj):
        let newObj = changedObjects.reduce(into: obj) { obj, x in
            let (changedKey, changedObj) = x
            if case .string(changedKey.type) = obj["__typename"], case .string(changedKey.id) = obj["id"] {
                // This is the referenced object: replace it
                if let incoming = changedObj {
                    // To prevent infinite recursion with references, this first traverses the existing object till it reaches the leaves
                    // And **only** updates leaf values: It never attempts to update objects
                    for (key, val) in obj {
                        switch val {
                        case .object, .list:
                            obj[key] = update(data: val, withChangedObjects: changedObjects)
                        default:
                            obj[key] = incoming[key]!.toValue()
                        }
                    }
                } else {
                    // If we can't find it in the cache then it no longer exists?
                    fatalError("Decide what to do here")
                }
            } else {
                obj = obj.mapValues { update(data: $0, withChangedObjects: changedObjects) }
            }
        }
        return .object(newObj)
       
    case .list(let objs):
        return .list(objs.map { update(data: $0, withChangedObjects: changedObjects) })
    default:
        return data
    }
}

