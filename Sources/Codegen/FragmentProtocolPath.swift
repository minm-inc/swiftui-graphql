import GraphQL
import OrderedCollections

/// An identifier to a protocol, specifically a protocol that forms part of a fragment.
/// It doesn't actually contain any information about the fragment itself. Use ``FragmentInfo`` to extract it.
struct FragmentProtocolPath: Hashable {
    let fragmentName: String
    enum Component: Hashable {
        static func == (lhs: FragmentProtocolPath.Component, rhs: FragmentProtocolPath.Component) -> Bool {
            switch (lhs, rhs) {
            case (.nested(let x), .nested(let y)): return x == y
            case (.type(let x), .type(let y)): return x === y
            default: return false
            }
        }

        func hash(into hasher: inout Hasher) {
            switch self {
            case .nested(let key): key.hash(into: &hasher)
            case .type(let type): type.hash(into: &hasher)
            }
        }
        
        case nested(key: String)
        case type(any GraphQLCompositeType)
        
        /// The name of the decl that the corresponding concrete type implementing this protocol component, should be named.
        var name: String {
            switch self {
            case .nested(let key): return key.firstUppercased
            case .type(let type): return type.name
            }
        }
    }
    let components: [Component]
    let isContainer: Bool
    
    init(fragmentName: String, components: [Component] = [], isContainer: Bool) {
        self.fragmentName = fragmentName
        self.components = components
        self.isContainer = isContainer
        assert(componentsInLegalOrder)
    }
    
    init(fragmentName: String, fragmentObject: MergedObject) {
        self.fragmentName = fragmentName
        self.components = []
        self.isContainer = !fragmentObject.isMonomorphic
    }
    
    func appendingNestedObject(_ object: MergedObject, withKey key: String) -> FragmentProtocolPath {
        FragmentProtocolPath(fragmentName: fragmentName,
                             components: components + [.nested(key: key)],
                             isContainer: !object.isMonomorphic)
    }
    
    func appendingTypeDiscrimination(type: any GraphQLCompositeType) -> FragmentProtocolPath {
        FragmentProtocolPath(fragmentName: fragmentName,
                             components: components + [.type(type)],
                             isContainer: false)
    }
    
    private var componentsInLegalOrder: Bool {
        var lastComponent: Component? = nil
        for component in components {
            if case .type = component {
                switch lastComponent {
                case .nested, nil:
                    break
                case .type:
                    return false
                }
            }
            lastComponent = component
        }
        return true
    }
    
    var protocolName: String {
        if isContainer {
            return "Contains" + qualifiedName
        } else {
            return qualifiedName
        }
    }
    
    
    var containerEnumName: String {
        assert(isContainer)
        return qualifiedName
    }
    
    var containerUnderlyingFragmentVarName: String {
        "__" + containerEnumName.firstLowercased
    }

    
    private var qualifiedName: String {
        components.map(\.name).reduce(fragmentName + "Fragment", +)
    }

}
