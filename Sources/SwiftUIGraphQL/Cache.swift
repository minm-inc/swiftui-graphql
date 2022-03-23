import Combine

public actor Cache {
    var store: [CacheKey: NormalizedCacheObject]
    let publisher = PassthroughSubject<(Set<CacheKey>, [CacheKey: NormalizedCacheObject]), Never>()
    init(store: [CacheKey: NormalizedCacheObject] = [:]) {
        self.store = store
    }
    
    @discardableResult
    func mergeCache(incoming: UnnormalizedCacheObject) -> [CacheKey: NormalizedCacheObject] {
        var changedObjs: [CacheKey: NormalizedCacheObject] = [:]
        func go(_ val: UnnormalizedCacheValue) -> NormalizedCacheValue {
            switch val {
            case .list(let list):
                return .list(list.map(go))
            case .object(let unrecursedObj):
                let obj = unrecursedObj.mapValues(go)
                guard case .string(let typename) = obj[CacheField(name: "__typename")],
                      case .string(let id) = obj[CacheField(name: "id")] else {
                    return .object(obj)
                }
                let cacheKey = CacheKey(type: typename, id: id)
                if let existingObj = store[cacheKey] {
                    // Update existing cached object
                    store[cacheKey] = mergeCacheObjects(existingObj, obj)
                    if store[cacheKey] != existingObj {
                        changedObjs[cacheKey] = store[cacheKey]
                    }
                } else {
                    // New addition to the cache
                    store[cacheKey] = obj
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
        let _ = go(.object(incoming))
        publisher.send((Set(changedObjs.keys), store))
        return changedObjs
    }
    
    private func mergeCacheObjects(_ x: NormalizedCacheObject, _ y: NormalizedCacheObject) -> NormalizedCacheObject {
        x.merging(y) { xval, yval in
            switch (xval, yval) {
            case let (.object(xobj), .object(yobj)):
                return .object(mergeCacheObjects(xobj, yobj))
            default:
                return yval
            }
        }
    }
    
    func normalize(cacheValue: UnnormalizedCacheValue) -> NormalizedCacheValue {
        switch cacheValue {
        case .list(let list):
            return .list(list.map(normalize))
        case .object(let unrecursedObj):
            let obj = unrecursedObj.mapValues(normalize)
            guard case .string(let typename) = obj[CacheField(name: "__typename")],
                  case .string(let id) = obj[CacheField(name: "id")] else {
                return .object(obj)
            }
            let cacheKey = CacheKey(type: typename, id: id)
            if store[cacheKey] != nil {
                return .reference(cacheKey)
            } else {
                return .object(obj)
            }
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

    public enum CacheUpdate: ExpressibleByDictionaryLiteral {
        case object([String: CacheUpdate])
        case update((NormalizedCacheValue) -> NormalizedCacheValue)
        
        public init(dictionaryLiteral elements: (String, CacheUpdate)...) {
            self = .object(Dictionary(uniqueKeysWithValues: elements))
        }
        
        public init(_ f: @escaping ([NormalizedCacheValue]) -> [NormalizedCacheValue]) {
            self = .update({ val in
                if case .list(let xs) = val {
                    return .list(f(xs))
                } else {
                    fatalError("Mismatching types")
                }
            })
        }
        
        public init(_ f: @escaping (NormalizedCacheValue) -> NormalizedCacheValue) {
            self = .update(f)
        }
    }
    
    public func update(_ key: CacheKey, with update: CacheUpdate) {
        guard let existing = store[key] else { return }
        
        func go(value: NormalizedCacheValue, update: CacheUpdate) -> NormalizedCacheValue {
            switch update {
            case .object(let fields):
                guard case .object(let obj) = value else {
                    fatalError("Mismatching types")
                }
                return .object(fields.reduce(into: obj) { acc, field in
                    let (name, update) = field
                    for (key, value) in acc.filter({ $0.key.name == name }) {
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
        publisher.send(([key], store))
    }
}

/// A top level key for items that can be cached
public struct CacheKey: Hashable {
    let type: String
    let id: String
    
    public init(type: String, id: String) {
        self.type = type
        self.id = id
    }
}

/// The key for any objects store in the cache, not just at the top level.
/// Keeps track of what arguments were used in the query.
public struct CacheField: Hashable {
    let name: String
    let args: [String: Value]
    init(name: String, args: [String: Value] = [:]) {
        self.name = name
        self.args = args
    }
}

/// Converts a ``Value`` object into a ``UnnormalizedCacheObject``, keeping track of what arguments were used in the selections.
///
/// Note that this **does not** create a normalized ``NormalizedCacheObject``. This is done inside ``Cache.mergeCache(incoming:)``
func cacheObject(from object: [String: Value], selections: [ResolvedSelection<Never>]) -> UnnormalizedCacheObject {
    var result: UnnormalizedCacheObject = [:]
    for selection in selections {
        switch selection {
        case .field(let field):
            guard let value = object[field.name] else { fatalError("Missing a value from this selection!") }
            let cacheField = CacheField(name: field.name, args: field.arguments)
            result[cacheField] = cacheValue(from: value, selections: field.selections)
        case .fragment(let typename, let selections):
            if object["__typename"] == .string(typename) {
                result.merge(cacheObject(from: object, selections: selections)) { $1 }
            }
        }
    }
    assert(containsSelections(selections: selections, cacheObject: result))
    return result
}

func cacheValue(from value: Value, selections: [ResolvedSelection<Never>]) -> UnnormalizedCacheValue {
    switch value {
    case let .object(xs):
        return .object(cacheObject(from: xs, selections: selections))
    case let .list(xs):
        return .list(xs.map { cacheValue(from: $0, selections: selections) })
    case let .int(x):
        return .int(x)
    case let .float(x):
        return .float(x)
    case let .boolean(x):
        return .boolean(x)
    case let .string(x):
        return .string(x)
    case let .enum(x):
        return .enum(x)
    case .null:
        return .null
    }
}

private func containsSelections(selections: [ResolvedSelection<Never>], cacheObject: UnnormalizedCacheObject) -> Bool {
    return selections.allSatisfy { selection in
        switch selection {
        case .field(let field):
            let matches = cacheObject.filter { $0.key.name == field.name }
            if matches.isEmpty { return false }
            func go(_ cacheValue: UnnormalizedCacheValue) -> Bool {
                switch cacheValue {
                case .list(let xs):
                    return xs.allSatisfy(go)
                case .object(let obj):
                    return containsSelections(selections: field.selections, cacheObject: obj)
                default:
                    return true
                }
            }
            return matches.values.allSatisfy(go)
        case .fragment(let typename, let selections):
            if cacheObject[CacheField(name: "__typename")] == .string(typename) {
                return containsSelections(selections: selections, cacheObject: cacheObject)
            } else {
                return true
            }
        }
    }
}

func cacheKey(from cacheObject: NormalizedCacheObject) -> CacheKey? {
    if case .string(let type) = cacheObject[CacheField(name: "__typename")],
       case .string(let id) = cacheObject[CacheField(name: "id")] {
        return CacheKey(type: type, id: id)
    } else {
        return nil
    }
}


public protocol CacheValueReference: Equatable {
    var cacheKey: CacheKey { get }
}
extension CacheKey: CacheValueReference {
    public var cacheKey: CacheKey { self }
}
extension Never: CacheValueReference {
    public var cacheKey: CacheKey { fatalError() }
}

/// An abstraction over ``NormalizedCacheValue`` and ``UnnormalizedCacheValue``
public enum CacheValue<Reference: CacheValueReference> {
    case boolean(Bool)
    case string(String)
    case int(Int)
    case float(Double)
    case `enum`(String)
    case reference(Reference)
    case object(CacheObject<Reference>)
    case list([CacheValue])
    case null
    // TODO: Handle custom scalars
    
    public subscript(_ field: String) -> CacheValue? {
        switch self {
        case .object(let obj):
            return obj.first { $0.key.name == field }?.value
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

/// A value that can be stored in the cache. It (should be) *normalized* and can contain references.
public typealias NormalizedCacheValue = CacheValue<CacheKey>

/// A value that has no references, i.e. all the references have been resolved, or it has not yet been normalized.
///
/// You get a ``UnnormalizedCacheValue`` by calling ``makeUnnormalizedCacheValue(from:selections:)`` with a ``ResolvedSelection``, as you need to know what fields you actually want to pull out when dealing with references. Otherwise you could end up in an infinite loop.
public typealias UnnormalizedCacheValue = CacheValue<Never>

func makeUnnormalizedCacheValue(from value: Value, selections: [ResolvedSelection<Never>]) -> UnnormalizedCacheValue {
    switch value {
    case .null:
        return .null
    case let .string(x):
        return .string(x)
    case let .int(x):
        return .int(x)
    case let .float(x):
        return .float(x)
    case let .boolean(x):
        return .boolean(x)
    case let .enum(x):
        return .enum(x)
    case let .object(xs):
        return .object(xs.reduce(into: [:]) { acc, x in
            let (name, val) = x
            let cacheField: CacheField
            let subSelections: [ResolvedSelection<Never>]
            if let selection = findSelection(name: name, in: selections) {
                cacheField = CacheField(name: name, args: selection.arguments)
                subSelections = selection.selections
            } else {
                cacheField = CacheField(name: name)
                subSelections = []
            }
            acc[cacheField] = makeUnnormalizedCacheValue(from: val, selections: subSelections)
        })
    case let .list(xs):
        return .list(xs.map { makeUnnormalizedCacheValue(from: $0, selections: selections) })
    }
}

extension UnnormalizedCacheValue {
    var value: Value {
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
            return .object(x.reduce(into: [:]) {
                $0[$1.key.name] = $1.value.value
            })
        case .list(let x):
            return .list(x.map { $0.value })
        case .`enum`(let x):
            return .`enum`(x)
        case .null:
            return .null
        }
    }
}

public typealias CacheObject<Reference: CacheValueReference> = [CacheField: CacheValue<Reference>]
public typealias NormalizedCacheObject = CacheObject<CacheKey>
typealias UnnormalizedCacheObject = CacheObject<Never>

public func cacheKey<Reference: CacheValueReference>(from cacheValue: CacheValue<Reference>) -> CacheKey? {
    switch cacheValue {
    case .object(let obj):
        if case .string(let type) = obj[CacheField(name: "__typename")],
           case .string(let id) = obj[CacheField(name: "id")] {
            return CacheKey(type: type, id: id)
        } else {
            return nil
        }
    case .reference(let cacheKey):
        return cacheKey.cacheKey
    default:
        return nil
    }
}


extension CacheValue: Equatable where Reference: Equatable {
    public static func == (lhs: CacheValue, rhs: CacheValue) -> Bool {
        switch (lhs, rhs) {
        case let (.boolean(x), .boolean(y)):
            return x == y
        case let (.string(x), .string(y)):
            return x == y
        case let (.int(x), .int(y)):
            return x == y
        case let (.float(x), .float(y)):
            return x == y
        case let (.`enum`(x), .`enum`(y)):
            return x == y
        case let (.object(x), .object(y)):
            return x == y
        case let (.reference(x), .reference(y)):
            return x == y
        case (.null, .null):
            return true
        default:
            return false
        }
    }
}
