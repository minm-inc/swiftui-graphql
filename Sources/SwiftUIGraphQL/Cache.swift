import Combine

public actor Cache {
    public typealias Updater = ((CacheObject, Cache) async -> Void)

    var store: [CacheKey: CacheObject]
    let publisher = PassthroughSubject<(Set<CacheKey>, [CacheKey: CacheObject]), Never>()
    init(store: [CacheKey: CacheObject] = [:]) {
        self.store = store
    }

    @discardableResult
    func mergeCache(incoming: [ObjectKey: Value], selection: ResolvedSelection<Never>, updater: Updater?) async -> (CacheObject, [CacheKey: CacheObject]) {
        var changedObjs: [CacheKey: CacheObject] = [:]
        
        func normalize(object: [ObjectKey: Value], fields: [ObjectKey: ResolvedSelection<Never>.Field]) -> CacheObject {
            object.reduce(into: [:]) { acc, x in
                let (objectKey, value) = x
                guard let field = fields[objectKey] else {
                    return
                }
                let key = NameAndArgumentsKey(name: field.name, args: field.arguments)
                acc[key] = go(value, selection: field.nested)
            }
        }
        
        func go(_ val: Value, selection: ResolvedSelection<Never>?) -> CacheValue {
            switch val {
            case .list(let list):
                return .list(list.map { go($0, selection: selection) })
            case .object(let unrecursedObj):
                guard let selection = selection else {
                    fatalError("Unexpected object without a selection")
                }
                
                let fields: [ObjectKey: ResolvedSelection<Never>.Field]
                if case .string(let typename) = extract(field: "__typename", from: unrecursedObj, selection: selection) {
                    // Note: Conditional selections are a superset of unconditional fields
                    fields = selection.conditional[typename] ?? selection.fields
                } else {
                    fields = selection.fields
                }
                
                let normalizedObj = normalize(object: unrecursedObj, fields: fields)
                
                guard let cacheKey = cacheKey(from: unrecursedObj, selection: selection) else {
                    return .object(normalizedObj)
                }
                
                if let existingObj = store[cacheKey] {
                    // Update existing cached object
                    store[cacheKey] = mergeCacheObjects(existingObj, normalizedObj)
                    if store[cacheKey] != existingObj {
                        changedObjs[cacheKey] = store[cacheKey]
                    }
                } else {
                    // New addition to the cache
                    store[cacheKey] = normalizedObj
                    changedObjs[cacheKey] = store[cacheKey]
                }
                return .reference(cacheKey)
            case let .string(x):
                return .string(x)
            case let .enum(x):
                return .enum(x)
            case let .boolean(x):
                return .boolean(x)
            case let .float(x):
                return .float(x)
            case let .int(x):
                return .int(x)
            case .null:
                return .null
            }
        }
        guard case .object(let res) = go(.object(incoming), selection: selection) else {
            fatalError()
        }
        await updater?(res, self)
        publisher.send((Set(changedObjs.keys), store))
        return (res, changedObjs)
    }
    
    private func mergeCacheObjects(_ x: CacheObject, _ y: CacheObject) -> CacheObject {
        x.merging(y) { xval, yval in
            switch (xval, yval) {
            case let (.object(xobj), .object(yobj)):
                return .object(mergeCacheObjects(xobj, yobj))
            default:
                return yval
            }
        }
    }

    public enum CacheUpdate: ExpressibleByDictionaryLiteral {
        case object([String: CacheUpdate])
        case update((CacheValue) -> CacheValue)
        
        public init(dictionaryLiteral elements: (String, CacheUpdate)...) {
            self = .object(Dictionary(uniqueKeysWithValues: elements))
        }
        
        public init(_ f: @escaping ([CacheValue]) -> [CacheValue]) {
            self = .update({ val in
                if case .list(let xs) = val {
                    return .list(f(xs))
                } else {
                    fatalError("Mismatching types")
                }
            })
        }
        
        public init(_ f: @escaping (CacheValue) -> CacheValue) {
            self = .update(f)
        }
    }
    
    public func update(_ key: CacheKey, with update: CacheUpdate) {
        guard let existing = store[key] else { return }
        
        func go(value: CacheValue, update: CacheUpdate) -> CacheValue {
            switch update {
            case .object(let fields):
                guard case .object(let obj) = value else {
                    fatalError("Mismatching types")
                }
                return .object(fields.reduce(into: obj) { acc, field in
                    let (name, update) = field
                    for (key, value) in acc.filter({ $0.key.name.name == name }) {
                        acc[key] = go(value: value, update: update)
                    }
                })
            case .update(let f):
                return f(value)
            }
        }
        
        guard case .object(let obj) = go(value: .object(existing), update: update) else {
            fatalError("Impossible")
        }
        store[key] = obj
    }

}
    
/// Takes a normalized cache object and expands all the references until it fulfills the selection
func value(from cacheObject: CacheObject, selection: ResolvedSelection<Never>, cacheStore: [CacheKey: CacheObject]) -> [ObjectKey: Value] {
    var res: [ObjectKey: Value] = [:]
    var fieldsToInclude = selection.fields
    if case .string(let typename) = cacheObject[NameAndArgumentsKey(name: "__typename")],
       let conditionalFields = selection.conditional[typename] {
        fieldsToInclude.merge(conditionalFields) { $1 }
    }
    for (objKey, field) in fieldsToInclude {
        let cacheKey = NameAndArgumentsKey(name: field.name, args: field.arguments)
        res[objKey] = value(from: cacheObject[cacheKey]!, selection: field.nested, cacheStore: cacheStore)
    }
    assert(contains(selection: selection, object: res))
    return res
}

func value(from cacheValue: CacheValue, selection: ResolvedSelection<Never>?, cacheStore: [CacheKey: CacheObject]) -> Value {
    switch cacheValue {
    case .reference(let ref):
        guard let selection = selection else {
            fatalError("Tried to expand a reference but there was no selection")
        }
        return .object(value(from: cacheStore[ref]!, selection: selection, cacheStore: cacheStore))
    case let .object(x):
        // TODO: If we get here, we can't be guaranteed that we'll be able to get complete data
        //        fatalError("A query returned a list of items that aren't identifiable: SwiftUIGraphQL cannot merge this in the cache")
        guard let selection = selection else {
            fatalError("Tried to expand an object but there was no selection")
        }
        return .object(value(from: x, selection: selection, cacheStore: cacheStore))
    case let .list(xs):
        guard let selection = selection else {
            fatalError("Tried to expand a list but there was no selection")
        }
        return .list(xs.map { value(from: $0, selection: selection, cacheStore: cacheStore) })
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
    }
}



/// A top level key for objects that can be cached, i.e. conform to ``Cacheable``
public struct CacheKey: Hashable {
    let type: String
    let id: String
    
    public init(type: String, id: String) {
        self.type = type
        self.id = id
    }
}

private func contains(selection: ResolvedSelection<Never>, object: [ObjectKey: Value]) -> Bool {
    var fieldsToCheck = selection.fields
    if case .string(let typename) = extract(field: "__typename", from: object, selection: selection),
       let conditionalFields = selection.conditional[typename] {
        fieldsToCheck.merge(conditionalFields) { $1 }
    }
    return selection.fields.allSatisfy { key, field in
        let matches = object.filter { $0.key == key }
        if matches.isEmpty { return false }
        func go(_ cacheValue: Value) -> Bool {
            switch cacheValue {
            case .list(let xs):
                return xs.allSatisfy(go)
            case .object(let obj):
                return contains(selection: field.nested!, object: obj)
            default:
                return true
            }
        }
        return matches.values.allSatisfy(go)
    }
}

public enum CacheValue: Equatable {
    case boolean(Bool)
    case string(String)
    case int(Int)
    case float(Double)
    case `enum`(String)
    case reference(CacheKey)
    case object(CacheObject)
    case list([CacheValue])
    case null
    // TODO: Handle custom scalars
    
    public subscript(_ key: NameAndArgumentsKey) -> CacheValue? {
        switch self {
        case .object(let obj):
            return obj.first { $0.key == key }?.value
        default:
            return nil
        }
    }
    
    public subscript(_ i: Int) -> CacheValue {
        switch self {
        case .list(let xs):
            return xs[i]
        default:
            fatalError("Not a list")
        }
    }
}

/// The key for any objects store in the cache, not just at the top level.
/// Keeps track of what arguments were used in the query.
public struct NameAndArgumentsKey: ExpressibleByStringLiteral, Hashable {
    public let name: FieldName
    public let args: [String: Value]
    public init(name: FieldName, args: [String: Value] = [:]) {
        self.name = name
        self.args = args
    }
    
    public init(stringLiteral value: StringLiteralType) {
        self.name = FieldName(value)
        self.args = [:]
    }
}

public typealias CacheObject = [NameAndArgumentsKey: CacheValue]

public func cacheKey(from object: [ObjectKey: Value], selection: ResolvedSelection<Never>) -> CacheKey? {
    guard case .string(let typename) = extract(field: "__typename", from: object, selection: selection),
          case .string(let id) = extract(field: "id", from: object, selection: selection) else {
        return nil
    }
    return CacheKey(type: typename, id: id)
}

func extract(field name: FieldName, from object: [ObjectKey: Value], selection: ResolvedSelection<Never>) -> Value? {
    if let field = selection.fields.first(where: { $0.value.name == name }) {
        return object[field.key]
    } else {
        return nil
    }
}

public func cacheKey(from cacheValue: CacheValue) -> CacheKey? {
    switch cacheValue {
    case .object(let obj):
        if case .string(let type) = obj[NameAndArgumentsKey(name: "__typename")],
           case .string(let id) = obj[NameAndArgumentsKey(name: "id")] {
            return CacheKey(type: type, id: id)
        } else {
            return nil
        }
    case .reference(let cacheKey):
        return cacheKey
    default:
        return nil
    }
}
