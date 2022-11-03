import OrderedCollections
import GraphQL
import SwiftUIGraphQL

/// For each protocol generated in Swift, this represents a graph of protocol inheritance hierarchies
///
/// Note that this is **not** specific to fragment protocols, but the graph is indeed initially constructed from fragments
class ProtocolConformance: Equatable {
    private(set) var inherits: [ProtocolConformance]
    private var inheritors: [ProtocolConformance] = []
    
    let type: ProtocolType
    enum ProtocolType {
        case plain(String)
        case fragment(FragmentProtocolPath)
    }
    
    var name: String {
        switch type {
        case .plain(let name): return name
        case .fragment(let path): return path.protocolName
        }
    }
    
    /// Every protocol this inherits, and everything they inherit etc.
    var ancestors: [ProtocolConformance] {
        inherits + inherits.flatMap(\.inherits)
    }
    
    init(type: ProtocolType, inherits: [ProtocolConformance] = []) {
        self.type = type
        self.inherits = inherits
    }
    
    var description: String {
        "\(name): \(inherits.map(\.name).joined(separator: ", "))"
    }

    func conforms(to x: ProtocolConformance) -> Bool {
        if x.name == name { return true }
        for y in inherits {
            if y.conforms(to: x) {
                return true
            }
        }
        return false
    }
    
    func inherit(_ x: ProtocolConformance) {
        guard !conforms(to: x) else { return }
        inherits.append(x)
        x.inheritors.append(self)
        // Remove any inheritances made redundant now
        inherits = inherits.filter { existing in
            existing === x || !existing.conforms(to: x)
        }
        
        // Remove any inheritances that x now supercedes
        inherits = inherits.filter { existing in
            existing === x || !x.conforms(to: existing)
        }
        
        inheritors.forEach { $0.uninheritUpwards(x) }
        assert(!conainsRedundantInherits)
    }
    
    private func uninheritUpwards(_ x: ProtocolConformance) {
        inherits = inherits.filter { $0 != x }
        x.inheritors.removeAll { $0 == self }
        inheritors.forEach { $0.uninheritUpwards(x) }
    }
    
    static private func newSelections(for object: MergedObject, withPath path: FragmentProtocolPath) -> [(FragmentProtocolPath, MergedObject.Selection)] {
        [(path, object.unconditional)] + object.conditional.map { type, selection in
            (path.appendingTypeDiscrimination(type: type.type), selection)
        }
    }
    
    private typealias InheritanceMap = [FragmentProtocolPath: OrderedSet<FragmentProtocolPath>]
    private typealias ObjectMap = [FragmentProtocolPath: MergedObject]
    
    private static func buildInheritanceMap(fragmentObjects: [String: MergedObject], schema: GraphQLSchema) -> (InheritanceMap, ObjectMap) {
        var inheritanceMap: InheritanceMap = [:]
        var objectMap: ObjectMap = [:]
        
        func insertInheritance(path: FragmentProtocolPath, inherits: FragmentProtocolPath) {
            if inheritanceMap.keys.contains(path) {
                inheritanceMap[path]!.append(inherits)
            } else {
                inheritanceMap[path] = [inherits]
            }
        }
        
        for (fragmentName, fragmentObject) in fragmentObjects {
            let path = FragmentProtocolPath(fragmentName: fragmentName, fragmentObject: fragmentObject)
            go(path: path, object: fragmentObject)
        }
        
        func go(path: FragmentProtocolPath, object: MergedObject) {
            objectMap[path] = object
            if inheritanceMap[path] == nil {
                inheritanceMap[path] = []
            }

            // First process the descendants
            for (key, field) in object.unconditional.fields {
                if let nested = field.nested {
                    go(path: path.appendingNestedObject(nested, withKey: key), object: nested)
                }
            }
            
            for (type, selection) in object.conditional {
                let typeDiscrimPath = path.appendingTypeDiscrimination(type: type.type)
                objectMap[typeDiscrimPath] = object
                if inheritanceMap[typeDiscrimPath] == nil {
                    inheritanceMap[typeDiscrimPath] = []
                }
                for (key, field) in selection.fields {
                    if let nested = field.nested {
                        go(path: typeDiscrimPath.appendingNestedObject(nested, withKey: key), object: nested)
                    }
                }
            }
            
            // Now decorate all the paths added here with fragment conformances
            for (fragmentName, conformance) in object.fragmentConformances {
                switch conformance {
                case .unconditional:
                    nestedInheritancesFor(xPath: path,
                                          xObject: object,
                                          inheritName: fragmentName,
                                          inheritObject: fragmentObjects[fragmentName]!,
                                          schema: schema)
                        .forEach(insertInheritance(path:inherits:))
                case .conditional(let fragType):
                    // The path that we're working on should be a container (ContainsFooFragment) protocol,
                    // since we're adding inheritances for its type discriminated sub-protocols e.g. ContainsFooTypeFragment
                    if !path.isContainer { break }
                    // Don't want to add any conformances to any other container protocols
                    if !fragmentObjects[fragmentName]!.isMonomorphic { break }
                    for type in object.conditional.keys where schema.isSubType(abstractType: fragType, maybeSubType: type.type) {
                        let typeDiscrimPath = path.appendingTypeDiscrimination(type: type.type)
                        // TODO: Do we need to insert the nested inheritences too? i.e. more than just the top level fragment protocol
                        insertInheritance(path: typeDiscrimPath,
                                          inherits: FragmentProtocolPath(fragmentName: fragmentName,
                                                                         fragmentObject: fragmentObjects[fragmentName]!))
                    }
                }
            }
        }
        return (inheritanceMap, objectMap)
    }
    
    private static func nestedInheritancesFor(xPath xStartPath: FragmentProtocolPath, xObject: MergedObject, inheritName: String, inheritObject: MergedObject, schema: GraphQLSchema) -> [FragmentProtocolPath: FragmentProtocolPath] {
        let inheritStartPath = FragmentProtocolPath(fragmentName: inheritName, fragmentObject: inheritObject)
        var queue = [(xStartPath, xObject, inheritStartPath, inheritObject)]
        var res: [FragmentProtocolPath: FragmentProtocolPath] = [:]
        
        while let (path, object, inheritPath, inheritObject) = queue.popLast() {
            res[path] = inheritPath
            
            var selections = [(path, object.unconditional, inheritPath, inheritObject.unconditional)]
            
            for (inheritType, inheritSelection) in inheritObject.conditional {
                for (type, selection) in object.conditional where schema.isSubType(abstractType: inheritType.type, maybeSubType: type.type) {
                    res[path.appendingTypeDiscrimination(type: type.type)] = inheritPath.appendingTypeDiscrimination(type: type.type)
                    selections.append((
                        path.appendingTypeDiscrimination(type: type.type),
                        selection,
                        inheritPath.appendingTypeDiscrimination(type: type.type),
                        inheritSelection
                    ))
                }
            }
            
            for (objectPath, objectSelection, inheritPath, inheritSelection) in selections {
                for (key, field) in inheritSelection.fields {
                    if let inheritNested = field.nested, let objectField = objectSelection.fields[key] {
                        guard let nested = objectField.nested else {
                            fatalError("There should also be a nested field on this object if the fragment object has a nested field")
                        }
                        queue.append((
                            objectPath.appendingNestedObject(nested, withKey: key),
                            nested,
                            inheritPath.appendingNestedObject(nested, withKey: key),
                            inheritNested
                        ))
                    }
                }
            }
        }
        
        return res
    }
    
    private static func orderInheritanceMap(_ inheritanceMap: InheritanceMap) -> some Sequence<FragmentProtocolPath> {
        var stack: [(FragmentProtocolPath, OrderedSet<FragmentProtocolPath>)] = Array(inheritanceMap)
        var order: OrderedSet<FragmentProtocolPath> = []
        while let (path, inherits) = stack.popLast() {
            order.appendOrPlaceLast(path)
            stack += inherits.map { ($0, inheritanceMap[$0]!) }
        }
        return order
    }
    
    static func buildConformanceGraph(fragmentObjects: [String: MergedObject], schema: GraphQLSchema) -> [FragmentProtocolPath: ProtocolConformance] {
        let (inheritanceMap, objectMap) = buildInheritanceMap(fragmentObjects: fragmentObjects, schema: schema)
        var res: [FragmentProtocolPath: ProtocolConformance] = [:]
        for path in orderInheritanceMap(inheritanceMap).reversed() {
            let conformance = ProtocolConformance(type: .fragment(path))
            inheritanceMap[path]!.map { res[$0]! }.forEach(conformance.inherit(_:))
            baseConformances(for: objectMap[path]!.unconditional.fields).forEach(conformance.inherit(_:))
            res[path] = conformance
        }
        return res
    }
    
    private static let cacheable = ProtocolConformance(
        type: .plain("Cacheable"),
        inherits: [codable, hashable]
    )
    private static let codable = ProtocolConformance(type: .plain("Codable"))
    private static let hashable = ProtocolConformance(type: .plain("Hashable"))
    private static let sendable = ProtocolConformance(type: .plain("Sendable"))

    /// The base protocol conformances that an object with the given set of fields will conform to
    static func baseConformances<T, U>(for fields: OrderedDictionary<String, SelectionField<T, U, any GraphQLOutputType>>) -> [ProtocolConformance] {
        if let field = fields["id"], field.name == "id", case .nonNull(.named("ID")) = graphqlTypeToSwiftUIGraphQLType(field.type) {
            return [.cacheable, .sendable]
        } else {
            return [.codable, .hashable, .sendable]
        }
    }
    
    static func == (lhs: ProtocolConformance, rhs: ProtocolConformance) -> Bool {
        lhs === rhs
    }
    
    private var conainsRedundantInherits: Bool {
        for inherit in inherits {
            let others = inherits.filter { $0 !== inherit }
            if others.contains(where: { $0.conforms(to: inherit) }) {
                return true
            }
        }
        return false
    }
}

fileprivate extension OrderedSet {
    mutating func appendOrPlaceLast(_ element: Element) {
        remove(element)
        append(element)
    }
}
