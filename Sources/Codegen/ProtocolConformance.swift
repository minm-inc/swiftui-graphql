import OrderedCollections
import SwiftUIGraphQL
class ProtocolConformance {
    let name: String
    var inherits: [ProtocolConformance]
    
    private init(name: String, inherits: [ProtocolConformance] = []) {
        self.name = name
        self.inherits = inherits
    }

    private func conforms(to x: ProtocolConformance) -> ProtocolConformance? {
        if x.name == name { return self }
        for y in inherits {
            if let res = y.conforms(to: x) {
                return res
            }
        }
        return nil
    }
    
    private func inherit(_ x: ProtocolConformance) {
        if conforms(to: x) == nil {
            inherits.append(x)
        }
    }
    
    static func buildConformanceGraph(fragmentSelections: [String: MergedSelection]) -> [FragmentPath: ProtocolConformance] {
        var stack = fragmentSelections.map { (FragmentPath(fragmentName: $0.0), $0.1) }
        
        var order: OrderedSet<FragmentPath> = []
        var selectionMap: [FragmentPath: MergedSelection] = [:]
        
        while let (path, selection) = stack.popLast() {
            if let path = order.remove(path) {
                order.append(path)
            } else {
                order.append(path)
            }
            selectionMap[path] = selection
            stack += selection.fragmentConformances.map {
                (FragmentPath(fragmentName: $0), fragmentSelections[$0]!)
            }
            stack += selection.fields.compactMap {
                if let nested = $0.value.nested {
                    return (path.appending(nestedObject: $0.key.firstUppercased), nested)
                } else {
                    return nil
                }
            }
            stack += selection.conditionals.map {
                (path.appending(nestedObject: $0.key), $0.value)
            }
        }
        
        var res: [FragmentPath: ProtocolConformance] = [:]
        for path in order.reversed() {
            let selection = selectionMap[path]!
            let conformance = ProtocolConformance(
                name: protocolName(for: path, selection: selection)
            )
            
            let inherited = selection.fragmentConformances.map { res[FragmentPath(fragmentName: $0)]! }
                + baseConformances(for: selection.fields)
            inherited.forEach { conformance.inherit($0) }
            res[path] = conformance
        }
        
        return res
    }
    
    /// If the resulting fragment is polymorphic, this gives the name for the container protocol, e.g. `ContainsFooFragment`,
    /// otherwise just `FooFragmentAndNestedObjects`
    private static func protocolName(for path: FragmentPath, selection: MergedSelection) -> String {
        if selection.conditionals.isEmpty {
            return path.fullyQualifiedName
        } else {
            return "Contains" + path.fullyQualifiedName
        }
    }
    
    private static let cacheable = ProtocolConformance(
        name: "Cacheable",
        inherits: [codable]
    )
    private static let codable = ProtocolConformance(name: "Codable")
    
    /// The base protocol conformances that an object with the given set of fields will conform to
    static func baseConformances<T, U>(for fields: OrderedDictionary<String, SelectionField<T, U>>) -> [ProtocolConformance] {
        if let field = fields["id"], field.name == "id", case .nonNull(.named("ID")) = field.type {
            return [.cacheable]
        } else {
            return [.codable]
        }
    }
}
