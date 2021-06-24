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

struct CacheKey: Hashable {
    let type: String
    let id: String
}

enum CacheObject: Equatable {
    case boolean(Bool)
    case string(String)
    case int(Int)
    case float(Double)
    case enumm(String)
    case reference(CacheKey)
    case object([String: CacheObject])
    case list([CacheObject])
    case null
    
    init(from: Value) {
        switch from {
        case .boolean(let x):
            self = .boolean(x)
        case .string(let x):
            self = .string(x)
        case .int(let x):
            self = .int(x)
        case .float(let x):
            self = .float(x)
        case .object(let x):
            self = .object(x.mapValues(CacheObject.init))
        case .list(let x):
            self = .list(x.map(CacheObject.init))
        case .enumm(let x):
            self = .enumm(x)
        case .null:
            self = .null
        }
    }
    
    func toValue(cache: [CacheKey: CacheObject]) -> Value {
        switch self {
        case .boolean(let x):
            return .boolean(x)
        case .string(let x):
            return .string(x)
        case .int(let x):
            return .int(x)
        case .float(let x):
            return .float(x)
        case .object(let x):
            return .object(x.mapValues { $0.toValue(cache: cache) })
        case .list(let x):
            return .list(x.map { $0.toValue(cache: cache) })
        case .enumm(let x):
            return .enumm(x)
        case .reference(let key):
            return cache[key]!.toValue(cache: cache)
        case .null:
            return .null
        }
    }
}

public actor GraphQLClient: ObservableObject {
    var cache: [CacheKey: CacheObject] = [:]
    let cachePublisher = PassthroughSubject<[CacheKey: CacheObject], Never>()
    
    let apiUrl: URL
    let headerCallback: () -> [String: String]
    
    public init(url: URL, withHeaders headerCallback: @escaping () -> [String: String]) {
        self.apiUrl = url
        self.headerCallback = headerCallback
    }
    
    @discardableResult private func mergeCache(incoming: Value) -> CacheKey? {
        switch incoming {
        case .object(let incoming):
            if case .string(let typename) = incoming["__typename"], case .string(let id) = incoming["id"] {
//                let cacheableFields = incoming.filter { !["__typename", "id"].contains($0.key) }
                let cacheEntries = incoming.mapValues { v -> CacheObject in
                    if let cacheKey = mergeCache(incoming: v) {
                        return .reference(cacheKey)
                    } else {
                        return CacheObject(from: v)
                    }
                }
                
                let cacheKey = CacheKey(type: typename, id: id)
                switch cache[cacheKey] {
                case .object(let existingObj):
                    cache[cacheKey] = .object(existingObj.merging(cacheEntries) { $1 })
                default:
                    cache[cacheKey] = .object(cacheEntries)
                }
                return cacheKey
            } else {
                incoming.values.forEach { mergeCache(incoming: $0) }
                return nil
            }
        case .list(let incoming):
            incoming.forEach { mergeCache(incoming: $0) }
            return nil
        default:
            return nil
        }
        
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
        guard let decodedData = graphqlResponse.data else {
            throw QueryError.invalid
        }
        
        let looseData = try! decoder.decode(Value.self, from: data)
        _ = mergeCache(incoming: looseData)
        cachePublisher.send(cache)
        
        return decodedData
    }
    
    func getCache() async -> [CacheKey: CacheObject] {
        return cache
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

// TODO: Do this in one pass with all the cache keys
func updateDataWithCache(data: Value, with cache: [CacheKey: CacheObject], newlyChangedKey: CacheKey) -> Value {
    switch data {
    case .object(let obj):
        if case .string(newlyChangedKey.type) = obj["__typename"], case .string(newlyChangedKey.id) = obj["id"] {
            // This is the referenced object: replace it
            if let incoming = cache[newlyChangedKey] {
                // TODO: Object merging strategies
                return incoming.toValue(cache: cache)
            }
            // If we can't find it in the cache then it no longer exists?
            fatalError("Decide what to do here")
        } else {
            return .object(obj.mapValues { updateDataWithCache(data: $0, with: cache, newlyChangedKey: newlyChangedKey) })
        }
    case .list(let objs):
        return .list(objs.map { updateDataWithCache(data: $0, with: cache, newlyChangedKey: newlyChangedKey)})
    default:
        return data
    }
}
