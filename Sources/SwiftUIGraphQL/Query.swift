//
//  Query.swift
//  
//
//  Created by Luke Lau on 25/06/2021.
//

import Combine
import SwiftUI

/**
 Need the ``DynamicProperty`` protocol otherwise the `@Environment` variables aren't initialized yet
 */
@propertyWrapper
public struct Query<Query: Queryable>: DynamicProperty {
    @EnvironmentObject public var client: GraphQLClient
    @StateObject var queryInternal = Operation<Query>()
    
    public init(mergePolicy: MergePolicy? = nil) {
        prepopulatedResponse = nil
        self.mergePolicy = mergePolicy
    }
    public var wrappedValue: Operation<Query> {
        get {
            if let prepopulatedResponse = prepopulatedResponse {
                let shim = Operation<Query>()
                shim.prepopulatedResponse = prepopulatedResponse
                return shim
            }
            queryInternal.client = client
            queryInternal.mergePolicy = mergePolicy
            return queryInternal
        }
    }
    
    private let prepopulatedResponse: QueryResponse<Query>?
    private let mergePolicy: MergePolicy?
    
    public init(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.prepopulatedResponse = try decoder.decode(QueryResponse<Query>.self, from: data)
        self.mergePolicy = nil
    }
    
    public init(from prepopulatedResponse: QueryResponse<Query>) {
        self.prepopulatedResponse = prepopulatedResponse
        self.mergePolicy = nil
    }
}

public class Operation<Response: Queryable>: ObservableObject {
    @Published var response: UnnormalizedCacheValue? = nil

    fileprivate var variables: Response.Variables?
    
    private var cacheSink: AnyCancellable?
    
    var client: GraphQLClient? {
        didSet {
            guard let client = client else {
                self.cacheSink?.cancel()
                self.cacheSink = nil
                return
            }
            Task {
                self.cacheSink = await client.cache.publisher
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] (changedKeys, cache) in
                        guard let self = self, let response = self.response else {
                            return
                        }
                        let resolvedSelections = substituteVariables(in: Response.selections, variableDefs: variablesToDict(self.variables) ?? [:])
                        self.response = update(value: response, selections: resolvedSelections, changedKeys: changedKeys, cache: cache)
                    }
            }
        }
    }

    var mergePolicy: MergePolicy? = nil
    var cacheUpdate: ((NormalizedCacheValue, Cache) async -> Void)? = nil
    
    public enum State {
        case loading
        case loaded(data: Response)
        case error
    }
    
    var state: State {
        guard let response = response else {
            return .loading
        }
        let data = try! ValueDecoder().decode(Response.self, from: response.value)
        return .loaded(data: data)
    }
    
    
    fileprivate var prepopulatedResponse: QueryResponse<Response>?
    
    func execute(variables: Response.Variables) async throws -> UnnormalizedCacheValue {
        guard let client = client else { fatalError("Client not set") }
        
        let variablesDict = variablesToDict(variables)
        let incoming: Value = try await client.query(query: Response.query, selections: Response.selections, variables: variablesDict)
        let merged: Value
        if let mergePolicy = mergePolicy, let response = response {
            merged = mergePolicy.merge(existing: response.value, incoming: incoming)
        } else {
            merged = incoming
        }
        let resolvedSelections = substituteVariables(in: Response.selections, variableDefs: variablesDict ?? [:])
        let cacheValue = makeUnnormalizedCacheValue(from: merged, selections: resolvedSelections)
        await MainActor.run {
            self.response = cacheValue
        }
        await cacheUpdate?(client.cache.normalize(cacheValue: cacheValue), client.cache)
        return cacheValue
    }

    public func callAsFunction() -> State where Response.Variables == NoVariables {
        callAsFunction(NoVariables())
    }
    
    public func callAsFunction(_ variables: Response.Variables) -> State {
        if let prepopulatedQuery = prepopulatedResponse {
            if let data = prepopulatedQuery.data {
                return .loaded(data: data)
            } else {
                return .error
            }
        }
        // Only make new request if variables have changed
        if (variables != self.variables) {
            self.variables = variables
            Task {
                do {
                    let _ = try await self.execute(variables: variables)
                } catch {
                    // TODO handle network errors
                    print(error)
                }
            }
        }
        return state
    }
}

private func unnormalizeCacheObject(from cacheObject: NormalizedCacheObject, cacheKey: CacheKey?, selections: [ResolvedSelection<Never>], cache: [CacheKey: NormalizedCacheObject]) -> [CacheField: UnnormalizedCacheValue] {
    var res: [CacheField: UnnormalizedCacheValue] = [:]
    for selection in selections {
        switch selection {
        case let .field(field):
            let storeField = CacheField(name: field.name, args: field.arguments)
            res[storeField] = unnormalizeCacheValue(from: cacheObject[storeField]!, selections: field.selections, cache: cache)
        case .fragment(cacheKey?.type, let selections):
            res.merge(unnormalizeCacheObject(from: cacheObject, cacheKey: cacheKey, selections: selections, cache: cache)) { $1 }
        default:
            break
        }
    }
    return res
}

private func unnormalizeCacheValue(from cacheValue: NormalizedCacheValue, selections: [ResolvedSelection<Never>], cache: [CacheKey: NormalizedCacheObject]) -> UnnormalizedCacheValue {
    switch cacheValue {
    case .reference(let ref):
        return .object(unnormalizeCacheObject(from: cache[ref]!, cacheKey: ref, selections: selections, cache: cache))
    case let .object(x):
        return .object(unnormalizeCacheObject(from: x, cacheKey: nil, selections: selections, cache: cache))
//        fatalError("A query returned a list of items that aren't identifiable: SwiftUIGraphQL cannot merge this in the cache")
    case let .string(x):
        return .string(x)
    case let .int(x):
        return .int(x)
    case let .float(x):
        return .float(x)
    case let .enum(x):
        return .enum(x)
    case let .boolean(x):
        return .boolean(x)
    case .null:
        return .null
    case let .list(xs):
        return .list(xs.map { unnormalizeCacheValue(from: $0, selections: selections, cache: cache) })
    }
}

func update(value: UnnormalizedCacheValue, selections: [ResolvedSelection<Never>], changedKeys: Set<CacheKey>, cache: [CacheKey: NormalizedCacheObject]) -> UnnormalizedCacheValue {
    switch value {
    case .object(let oldObj):
        let recursed = Dictionary(uniqueKeysWithValues: oldObj.compactMap { key, val -> (CacheField, UnnormalizedCacheValue)? in
            guard let selection = findSelection(name: key.name, in: selections) else {
                return nil
            }
            return (
                key,
                update(
                    value: val,
                    selections: selection.selections,
                    changedKeys: changedKeys,
                    cache: cache
                )
            )
        })
        guard let existingCacheKey = cacheKey(from: .object(recursed)) else {
            return .object(recursed)
        }
        if let changedObj = cache[existingCacheKey] {
            let incomingObj = unnormalizeCacheObject(from: changedObj, cacheKey: existingCacheKey, selections: selections, cache: cache)
            return .object(oldObj.merging(incomingObj) { $1 })
        } else {
            return .object(recursed)
        }
    case .list(let objs):
        return .list(objs.map { update(value: $0, selections: selections, changedKeys: changedKeys, cache: cache) })
    default:
        return value
    }
}

public struct MergePolicy: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, MergePolicy)...) {
        self.fields = Dictionary(uniqueKeysWithValues: elements)
        self.f = nil
    }
    
    public init(_ f: @escaping (SwiftUIGraphQL.Value, SwiftUIGraphQL.Value) -> SwiftUIGraphQL.Value) {
        self.f = f
        self.fields = [:]
    }
    
    static let `default`: MergePolicy = [:]
    
    public typealias Key = String
    public typealias Value = MergePolicy
    
    let f: ((SwiftUIGraphQL.Value, SwiftUIGraphQL.Value) -> SwiftUIGraphQL.Value)?
    let fields: [String: MergePolicy]
    
    func merge(existing: SwiftUIGraphQL.Value, incoming: SwiftUIGraphQL.Value) -> SwiftUIGraphQL.Value {
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

//public class QueryWatcher<Query: Queryable & Encodable>: Operation<Query> {
//    var state: State {
//        if let response = response {
//            let data = try! ValueDecoder().decode(Query.self, from: response.value)
//            return .loaded(data: data)
//        } else {
//            return .loading
//        }
//    }
////    @Published public internal(set) var state: State = .loading
//    public enum State {
//        case loading
//        case loaded(data: Query)
//        case error
//    }
//}
