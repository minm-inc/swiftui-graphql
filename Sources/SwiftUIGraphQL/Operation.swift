//
//  Query.swift
//  
//
//  Created by Luke Lau on 25/06/2021.
//

import Combine
import Foundation


/// Watches the cache for any changes to the cache and updates its response
public class Operation<Response: Queryable>: ObservableObject {
    var response: Value? = nil {
        didSet {
            if let response = response {
                let data = try! ValueDecoder(scalarDecoder: client!.scalarDecoder).decode(Response.self, from: response)
                self.state = .loaded(data: data)
            } else {
                self.state = .loading
            }
        }
    }

    var variables: Response.Variables?
    
    private var cacheSink: AnyCancellable?
    
    var client: GraphQLClient? {
        didSet {
            guard let client = client else {
                self.cacheSink?.cancel()
                self.cacheSink = nil
                return
            }
            self.cacheSink = client.cache.publisher
                .receive(on: DispatchQueue.main)
                .sink { [unowned self] (changedKeys, cacheStore) in
                    guard let response = self.response else {
                        return
                    }
                    let selection = substituteVariables(in: Response.selection, variableDefs: variablesToObject(self.variables) ?? [:])
                    self.response = update(value: response, selection: selection, changedKeys: changedKeys, cacheStore: cacheStore)
                }
        }
    }

    var mergePolicy: MergePolicy? = nil
    var cacheUpdater: Cache.Updater? = nil
    
    public enum State {
        case loading
        case loaded(data: Response)
        case error(QueryError)
    }
    
    @Published public private(set) var state: State = .loading
    
    internal func execute(variables: Response.Variables) async throws -> Value {
        guard let client = client else { fatalError("Client not set") }
        
        let variablesObj = variablesToObject(variables)
        let incoming: Value = try await client.query(query: Response.query, selection: Response.selection, variables: variablesObj, cacheUpdater: cacheUpdater)
        let merged: Value
        if let mergePolicy = mergePolicy, let response = response {
            merged = mergePolicy.merge(existing: response, incoming: incoming)
        } else {
            merged = incoming
        }
        await MainActor.run {
            self.response = merged
        }
        return merged
    }
    
    
    private func update(value val: Value, selection: ResolvedSelection<Never>, changedKeys: Set<CacheKey>, cacheStore: [CacheKey: CacheObject]) -> Value {
        switch val {
        case .object(let oldObj):
            let recursed = Dictionary(uniqueKeysWithValues: oldObj.compactMap { key, val -> (ObjectKey, Value)? in
                let typename: String?
                if case .string(let s) = extract(field: "__typename", from: oldObj, selection: selection) {
                    typename = s
                } else {
                    typename = nil
                }
                if let field = findField(key: key, onType: typename, in: selection),
                   let nested = field.nested {
                    return (
                        key,
                        update(
                            value: val,
                            selection: nested,
                            changedKeys: changedKeys,
                            cacheStore: cacheStore
                        )
                    )
                } else {
                    return (key, val)
                }
            })
            guard let existingCacheKey = cacheKey(from: recursed, selection: selection),
                  changedKeys.contains(existingCacheKey),
                  let changedObj = cacheStore[existingCacheKey] else {
                return .object(recursed)
            }
            
            let incomingObj = value(from: changedObj, selection: selection, cacheStore: cacheStore)
            return .object(oldObj.merging(incomingObj) { $1 })
        case .list(let objs):
            return .list(objs.map { update(value: $0, selection: selection, changedKeys: changedKeys, cacheStore: cacheStore) })
        default:
            return val
        }
    }
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

