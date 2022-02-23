class Cache {
    var store: [CacheKey: CacheObject]
    init(store: [CacheKey: CacheObject] = [:]) {
        self.store = store
    }
    func mergeCache(incoming: Value) {
        func go(_ val: CacheValue) -> CacheValue {
            switch val {
            case .list(let list):
                return .list(list.map(go))
            case .object(let unrecursedObj):
                let obj = unrecursedObj.mapValues(go)
                guard case .string(let typename) = obj["__typename"], case .string(let id) = obj["id"] else {
                    return .object(obj)
                }
                let cacheKey = CacheKey(type: typename, id: id)
                if let existingObj = store[cacheKey] {
                    // Update existing cached object
                    store[cacheKey] = mergeCacheObjects(existingObj, obj)
                } else {
                    // New addition to the cache
                    store[cacheKey] = obj
                }
                return .reference(cacheKey)
            default:
                return val
            }
        }
        let _ = go(CacheValue(from: incoming))
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

}

struct CacheKey: Hashable {
    let type: String
    let id: String
}

typealias CacheObject = [String: CacheValue]

enum CacheValue: Equatable {
    case boolean(Bool)
    case string(String)
    case int(Int)
    case float(Double)
    case `enum`(String)
    case reference(CacheKey)
    case object(CacheObject)
    case list([CacheValue])
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
            self = .object(x.mapValues(CacheValue.init))
        case .list(let x):
            self = .list(x.map(CacheValue.init))
        case .`enum`(let x):
            self = .`enum`(x)
        case .null:
            self = .null
        }
    }
    
    func toValue() -> Value {
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
            return .object(x.mapValues { $0.toValue() })
        case .list(let x):
            return .list(x.map { $0.toValue() })
        case .`enum`(let x):
            return .`enum`(x)
        case .reference:
            fatalError("Can't convert this to a value (potential for infinite loop)")
        case .null:
            return .null
        }
    }
}
