public actor Cache {
    public typealias Updater = (@Sendable (CacheObject, Cache) async -> Void)

    init(store: [CacheKey: CacheObject] = [:]) {
        self.store = Store(initialStore: store)
    }

    /// Keeps track of whats changed when merging stuff in
    struct Store {
        private(set) var store: [CacheKey: CacheObject]
        private var changes: [CacheKey: ObjectChange] = [:]

        init(initialStore: [CacheKey: CacheObject]) {
            var initialStore = initialStore
            if initialStore[.queryRoot] == nil {
                initialStore[.queryRoot] = [:]
            }
            self.store = initialStore
        }

        subscript(cacheKey: CacheKey) -> CacheObject? {
            get {
                store[cacheKey]
            }
            set {
                store[cacheKey] = newValue
                // TODO: Make this smarter
                changes[cacheKey] = .wholeThing
            }
        }

        mutating func mergeCacheObject(_ incoming: CacheObject, into cacheKey: CacheKey) {
            if store[cacheKey] == nil {
                store[cacheKey] = incoming
                changes[cacheKey] = .wholeThing
            } else {
                let changes = merge(incoming, into: &store[cacheKey]!)
                if !changes.isEmpty {
                    recordChange(.partial(changes), on: cacheKey)
                }
            }
        }

        private func merge(_ incoming: CacheObject, into existing: inout CacheObject) -> [NameAndArgumentsKey: ObjectChange] {
            var changes: [NameAndArgumentsKey: ObjectChange] = [:]
            for (key, incomingVal) in incoming {
                let existingVal = existing[key]
                switch (existingVal, incomingVal) {
                case (.object(var existingNested), .object(let incomingNested)):
                    let nestedChanges = merge(incomingNested, into: &existingNested)
                    if !nestedChanges.isEmpty {
                        changes[key] = .partial(nestedChanges)
                        existing[key] = .object(existingNested)
                    }
                default:
                    if incomingVal != existingVal {
                        changes[key] = .wholeThing
                        existing[key] = incomingVal
                    }
                }
            }
            return changes
        }

        mutating func clear() {
            store.removeAll()
            changes[.queryRoot] = .wholeThing
            store[.queryRoot] = [:]
        }

        // MARK: - Change tracking

        private enum ObjectChange {
            case wholeThing
            case partial([NameAndArgumentsKey: ObjectChange])

            static func merge(_ x: ObjectChange, _ y: ObjectChange) -> ObjectChange {
                switch (x, y) {
                case (.wholeThing, _), (_, .wholeThing):
                    return .wholeThing
                case let (.partial(x), .partial(y)):
                    return .partial(x.merging(y, uniquingKeysWith: merge(_:_:)))
                }
            }
        }

        mutating func clearChanges() { changes.removeAll() }

        private mutating func recordChange(_ change: ObjectChange, on cacheKey: CacheKey) {
            if let existing = changes[cacheKey] {
                changes[cacheKey] = ObjectChange.merge(existing, change)
            } else {
                changes[cacheKey] = change
            }
        }

        func selectionChanged(_ selection: ResolvedSelection<Never>, on cacheKey: CacheKey) -> Bool {
            switch changes[cacheKey] {
            case .wholeThing:
                return true
            case .partial(let changedFields):
                if didSelectionChange(cacheObject: store[cacheKey]!, changedFields: changedFields, selection: selection) {
                    return true
                } else {
                    break
                }
            case nil:
                break
            }
            if let cacheObj = store[cacheKey] {
                return collectReferences(cacheObject: cacheObj, selection: selection).contains { nestedCacheKey, nestedSelection in
                    selectionChanged(nestedSelection, on: nestedCacheKey)
                }
            } else {
                return true
            }
        }

        private func didSelectionChange(cacheObject: CacheObject, changedFields: [NameAndArgumentsKey: ObjectChange], selection: ResolvedSelection<Never>) -> Bool {
            for (_, field) in applicableFieldsForCacheObject(cacheObject, selection: selection) {
                let key = NameAndArgumentsKey(field: field)
                if let change = changedFields[key] {
                    switch change {
                    case .wholeThing:
                        return true
                    case .partial(let nestedChanges):
                        guard case .object(let nestedCacheObject) = cacheObject[key]! else { fatalError() }
                        if didSelectionChange(cacheObject: nestedCacheObject,
                                              changedFields: nestedChanges,
                                              selection: field.nested!) {
                            return true
                        }
                    }
                }
            }
            return false
        }

        /// Gets all other cache objects that `cacheObject` directly references (not transitive)
        private func collectReferences(cacheObject: CacheObject, selection: ResolvedSelection<Never>) -> [(CacheKey, ResolvedSelection<Never>)] {
            var refs: [(CacheKey, ResolvedSelection<Never>)] = []

            for field in applicableFieldsForCacheObject(cacheObject, selection: selection).values {
                if let cacheValue = cacheObject[NameAndArgumentsKey(field: field)],
                   let nested = field.nested {
                    refs += collectReferences(cacheValue: cacheValue, selection: nested)
                }
            }
            return refs
        }

        private func collectReferences(cacheValue: CacheValue, selection: ResolvedSelection<Never>) -> [(CacheKey, ResolvedSelection<Never>)] {
            switch cacheValue {
            case .reference(let key):
                return [(key, selection)]
            case .object(let obj):
                return collectReferences(cacheObject: obj, selection: selection)
            case .list(let xs):
                return xs.flatMap { collectReferences(cacheValue: $0, selection: selection) }
            default:
                return []
            }
        }
    }

    private(set) var store: Store

    /// Updates the cache with the response from a server, and notifies any downstream subscribers that the cache changed (if it did)
    /// - Parameters:
    ///   - incoming: The object from a server response. This must be an object on the Query root type.
    ///   - selection: The selection that was used in the request.
    ///   - updater: An optional function to run after updating the cache and before notifying subscribers, that tweaks the cache.
    func mergeQuery(_ incoming: [ObjectKey: Value], selection: ResolvedSelection<Never>, updater: Updater?) async {
        guard case .object(let res) = normalizeAndMerge(incoming, selection: selection) else {
            fatalError()
        }

        store.mergeCacheObject(res, into: .queryRoot)

        await updater?(res, self)
        flushChanges()
    }

    /// The same as ``mergeQuery``, but to be used for operations on the Mutation root type
    func mergeMutation(_ incoming: [ObjectKey: Value], selection: ResolvedSelection<Never>, updater: Updater?) async {
        guard case .object(let res) = normalizeAndMerge(incoming, selection: selection) else {
            fatalError()
        }
        await updater?(res, self)
        flushChanges()
    }

    public func clear() {
        store.clear()
        flushChanges()
    }

    private func normalizeAndMerge(_ object: [ObjectKey: Value], selection: ResolvedSelection<Never>) -> CacheValue {
        let fields: [ObjectKey: ResolvedSelection<Never>.Field]
        if case .string(let typename) = extract(field: "__typename", from: object, selection: selection) {
            // Note: Conditional selections are a superset of unconditional fields
            fields = selection.conditional[typename] ?? selection.fields
        } else {
            fields = selection.fields
        }

        let normalizedObj: CacheObject = object.reduce(into: [:]) { acc, x in
            let (objectKey, value) = x
            guard let field = fields[objectKey] else {
                return
            }
            let key = NameAndArgumentsKey(field: field)
            acc[key] = normalizeAndMerge(value, selection: field.nested)
        }

        guard let cacheKey = cacheKey(from: object, selection: selection) else {
            return .object(normalizedObj)
        }

        store.mergeCacheObject(normalizedObj, into: cacheKey)

        return .reference(cacheKey)
    }

    private func normalizeAndMerge(_ val: Value, selection: ResolvedSelection<Never>?) -> CacheValue {
        switch val {
        case .list(let list):
            return .list(list.map { normalizeAndMerge($0, selection: selection) })
        case .object(let obj):
            guard let selection else {
                fatalError("Unexpected object without a selection")
            }
            return normalizeAndMerge(obj, selection: selection)
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

    private var continuations: [Int: (ResolvedSelection<Never>, CacheKey, AsyncStream<[ObjectKey: Value]?>.Continuation)] = [:]
    private var nextContinuationKey = 0
    private func removeContinuation(forKey key: Int) {
        continuations.removeValue(forKey: key)
    }

    func listenToChanges(selection: ResolvedSelection<Never>, on cacheKey: CacheKey) -> AsyncStream<[ObjectKey: Value]?> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let key = nextContinuationKey
            continuations[key] = (selection, cacheKey, continuation)
            nextContinuationKey += 1
            continuation.onTermination = { termination in
                Task {
                    await self.removeContinuation(forKey: key)
                }
            }
       }
    }

    public enum CacheUpdate: ExpressibleByDictionaryLiteral, Sendable {
        case object([String: CacheUpdate])
        case update(@Sendable (CacheValue) -> CacheValue)
        
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
        
        public init(_ f: @escaping @Sendable (CacheValue) -> CacheValue) {
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

    func flushChanges() {
        for (selection, cacheKey, continuation) in continuations.values where store.selectionChanged(selection, on: cacheKey) {
            if let object = value(from: store[cacheKey]!, selection: selection) {
                continuation.yield(object)
            } else {
                continuation.yield(nil)
            }
        }
        store.clearChanges()
    }

    /// Takes a normalized cache object and expands all the references until it fulfills the selection
    /// - Returns: The object for the selection, or nil if it wasn't able to expand everything.
    func value(from cacheObject: CacheObject, selection: ResolvedSelection<Never>) -> [ObjectKey: Value]? {
        var res: [ObjectKey: Value] = [:]
        for (objKey, field) in applicableFieldsForCacheObject(cacheObject, selection: selection) {
            let key = NameAndArgumentsKey(field: field)
            guard let fieldValue = cacheObject[key],
                  let resValue = value(from: fieldValue, selection: field.nested) else {
                return nil
            }
            res[objKey] = resValue
        }
        assert(contains(selection: selection, object: res))
        return res
    }

    func value(from cacheValue: CacheValue, selection: ResolvedSelection<Never>?) -> Value? {
        switch cacheValue {
        case .reference(let ref):
            guard let selection else {
                fatalError("Tried to expand a reference on \(ref) but there was no selection")
            }
            return value(from: store[ref]!, selection: selection).map { .object($0) }
        case let .object(x):
            // TODO: If we get here, we can't be guaranteed that we'll be able to get complete data
            //        fatalError("A query returned a list of items that aren't identifiable: SwiftUIGraphQL cannot merge this in the cache")
            guard let selection = selection else {
                fatalError("Tried to expand an object but there was no selection")
            }
            return value(from: x, selection: selection).map(Value.object(_:))
        case let .list(xs):
            guard let selection = selection else {
                fatalError("Tried to expand a list but there was no selection")
            }
            let recursed = xs.map { value(from: $0, selection: selection) }
            if recursed.contains(where: { $0 == nil }) {
                return nil
            } else {
                return .list(recursed.map { $0! })
            }
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

}

/// A top level key for objects that can be cached, i.e. conform to ``Cacheable``
public enum CacheKey: Hashable, Sendable {
    case object(typename: String, id: ID)
    case queryRoot
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

/// Returns the fields for the selection, given the current `cacheObject`'s type (e.g. taking into account `__typename`)
func applicableFieldsForCacheObject(_ cacheObject: CacheObject, selection: ResolvedSelection<Never>) -> [ObjectKey: ResolvedSelection<Never>.Field] {
    var fieldsToInclude = selection.fields
    if case .string(let typename) = cacheObject[NameAndArgumentsKey(name: "__typename")],
       let conditionalFields = selection.conditional[typename] {
        fieldsToInclude.merge(conditionalFields) { $1 }
    }
    return fieldsToInclude
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

    init(field: ResolvedSelection<Never>.Field) {
        self.name = field.name
        self.args = field.arguments
    }
}

public typealias CacheObject = [NameAndArgumentsKey: CacheValue]

public func lookup(_ names: FieldName..., ignoringArgumentsIn object: CacheObject) -> CacheValue? {
    lookup(names: names, ignoringArgumentsIn: object)
}
private func lookup<T: RandomAccessCollection>(names: T, ignoringArgumentsIn object: CacheObject) -> CacheValue? where T.Element == FieldName {
    if let name = names.first {
        if let child = object.first(where: { $0.key.name == name })?.value {
            if case .object(let childObject) = child {
                return lookup(names: names.dropFirst(), ignoringArgumentsIn: childObject)
            } else {
                return child
            }
        } else {
            return nil
        }
    } else {
        return .object(object)
    }
}

public func cacheKey(from object: [ObjectKey: Value], selection: ResolvedSelection<Never>) -> CacheKey? {
    guard case .string(let typename) = extract(field: "__typename", from: object, selection: selection),
          case .string(let id) = extract(field: "id", from: object, selection: selection) else {
        return nil
    }
    return .object(typename: typename, id: id)
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
        if case .string(let typename) = obj[NameAndArgumentsKey(name: "__typename")],
           case .string(let id) = obj[NameAndArgumentsKey(name: "id")] {
            return .object(typename: typename, id: id)
        } else {
            return nil
        }
    case .reference(let cacheKey):
        return cacheKey
    default:
        return nil
    }
}
