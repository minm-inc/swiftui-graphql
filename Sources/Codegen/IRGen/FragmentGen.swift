import SwiftSyntax
import OrderedCollections
import SwiftUIGraphQL

func gen(fragment: MergedSelection, named name: String, fragmentInfo: FragmentInfo) -> [Decl] {
    let following = fragment.fragmentConformances.map {
        (FragmentPath(fragmentName: $0), fragmentInfo.selections[$0]!)
    }
    let fragProto = FragProtoGenerator(fragmentInfo: fragmentInfo)
        .gen(fragProtoFor: fragment, following: following, currentPath: FragmentPath(fragmentName: name))
    return gen(fragProto: fragProto, named: name, fragmentInfo: fragmentInfo)
}

enum FragProto {
    case monomorphic(path: FragmentPath, fields: OrderedDictionary<String, Field>, conformance: ProtocolConformance)
    case polymorphic(path: FragmentPath, fields: OrderedDictionary<String, Field>, cases: OrderedDictionary<String, Case>, conformance: ProtocolConformance)
    
    enum Field {
        case variableGetter(name: String, type: `Type`, object: FragProto?)
        case whereClause(FragProto)
    }
    
    struct Case {
        let fragProto: FragProto
        let type: CaseType
        enum CaseType {
            case associatedType
            case whereClause
        }
    }
    
    var conformance: ProtocolConformance {
        switch self {
        case .monomorphic(_, _, let conformance):
            return conformance
        case .polymorphic(_, _, _, let conformance):
            return conformance
        }
    }
}

private class FragProtoGenerator {
    let fragmentInfo: FragmentInfo
    
    init(fragmentInfo: FragmentInfo) {
        self.fragmentInfo = fragmentInfo
    }
    
    func gen(fragProtoFor object: MergedSelection, following fragmentObjects: [(FragmentPath, MergedSelection)], currentPath: FragmentPath) -> FragProto {
        let fields: OrderedDictionary<String, FragProto.Field> = object.fields.reduce(into: [:]) { acc, x in
            let (key, field) = x
            let shadowed = object.fragmentConformances.contains {
                fragmentInfo.selections[$0]!.selectedKeys().contains(key)
            }
            let nestedFragmentObjects: [(FragmentPath, MergedSelection)] =
                fragmentObjects.compactMap { path, obj in
                    if let nestedObj = obj[key, forTypename: field.type.underlyingName]?.nested {
                        return (path.appending(nestedObject: key), nestedObj)
                    } else {
                        return nil
                    }
                }
            let nestedPath = currentPath.appending(nestedObject: key.firstUppercased)
            if shadowed {
                // If it's shadowed, then instead of defining the field we instead constrain
                // the shadowing definition from the other protocol.
                if let nested = field.nested {
                    acc[key] = .whereClause(gen(
                        fragProtoFor: nested,
                        following: nestedFragmentObjects,
                        currentPath: nestedPath
                    ))
                }
                // If it's shadowed and it's not nested, then we don't need to define anything
            } else {
                // If it's not shadowed then we need to define it
                acc[key] = .variableGetter(
                    name: field.name.name,
                    type: field.type,
                    object: field.nested.map { selection in
                        gen(fragProtoFor: selection,
                            following: nestedFragmentObjects,
                            currentPath: nestedPath
                        )
                    }
                )
            }
        }
        let cases: OrderedDictionary<String, FragProto.Case> = object.conditionals.reduce(into: [:]) { acc, x in
            let (typeCondition, selection) = x
            let shadowed = object.fragmentConformances.contains {
                fragmentInfo.selections[$0]!.conditionals.keys.contains(typeCondition)
            }
            let fragProto = gen(
                fragProtoFor: selection,
                following: fragmentObjects,
                currentPath: currentPath.appending(nestedObject: typeCondition)
            )
            acc[typeCondition] = FragProto.Case(
                fragProto: fragProto,
                type: shadowed ? .whereClause : .associatedType
            )
        }
        
        let protocolConformance = fragmentInfo.conformanceGraph[currentPath]!
        
        if cases.isEmpty {
            return .monomorphic(path: currentPath, fields: fields, conformance: protocolConformance)
        } else {
            return .polymorphic(path: currentPath, fields: fields, cases: cases, conformance: protocolConformance)
        }
    }
}

private func gen(fragProto root: FragProto, named name: String, fragmentInfo: FragmentInfo) -> [Decl] {
    var decls: [Decl] = []
    var fragProtosToGen = [root]
    while let fragProto = fragProtosToGen.popLast() {
        let fields: OrderedDictionary<String, FragProto.Field>
        
        var whereClauses: [Decl.WhereClause] = []
        var declsInProtocol: [Decl] = []
        
        switch fragProto {
        case let .monomorphic(_, fragProtoFields, _):
            // This is a bog standard fragment that will be a protocol, continue
            // on and generate the accessors for the fields below
            fields = fragProtoFields
        case let .polymorphic(path, fragProtoFields, cases, _):
            fields = fragProtoFields
            
            // If the fragment is polymorphic, then the protocol becomes `ContainsFooFragment`
            // and we need to add a `__fooFragment() -> FooFragment<A,B>` requirement to the protocol, as well as a FooFragment<A,B> enum
            //
            // protocol ContainsFooFragment {
            //   associatedtype A: FooFragmentA
            //   associatedtype B: FooFragmentB
            //   var __fooFragment: FooFragment<A, B> { get }
            // }
            // enum FooFragment<A: FooFragmentA, B: FooFragmentB> {
            //   case a(A), b(B)
            // }
            // protocol FooFragmentA { ... }
            // protocol FooFragmentB { ... }
            
            declsInProtocol.append(.let(
                name: "__\(path.fullyQualifiedName.firstLowercased)",
                type: fragmentInfo.makeUnderlyingFragmentEnumType(path: path),
                accessor: .get()
            ))
            
            // Put the case protocols onto the todo list
            for (typename, `case`) in cases {
                fragProtosToGen.append(`case`.fragProto)
                switch `case`.type {
                case .associatedType:
                    declsInProtocol.append(
                        .associatedtype(name: typename, inherits: `case`.fragProto.conformance.name)
                    )
                case .whereClause:
                    whereClauses.append(
                        Decl.WhereClause(associatedType: typename, constraint: `case`.fragProto.conformance.name)
                    )
                }
                // And an add an associated type for said protocol
            }
            
            // Generate the enum
            decls.append(
                .enum(
                    name: path.fullyQualifiedName,
                    cases: cases.keys.map { Decl.Case(name: $0.firstLowercased, nestedTypeName: $0) },
                    decls: [],
                    conforms: ["Hashable"],
                    defaultCase: Decl.Case(name: "__other", nestedTypeName: nil),
                    genericParameters: cases.map { typeName, `case` in
                        Decl.GenericParameter(
                            identifier: typeName,
                            constraint: .named(
                                `case`.fragProto.conformance.name
                            )
                        )
                    }
                )
            )
        }
        
        // Now generate the accessor requirements for the protocol
        for (key, field) in fields {
            switch field {
            case .variableGetter(_, var type, let object):
                if let nestedFragProto = object {
                    // Ok this field has a nested object, so we need to generate another protocol
                    // for said nested object:
                    // protocol FooFragment
                    //   associatedtype A: FooFragmentA
                    //   var a: A { get }
                    // }
                    // protocol FooFragmentA { ... }
                    fragProtosToGen.append(nestedFragProto)
                    
                    // And declare an associated type on it
                    // The type of a nested object is always just the name of the key
                    // Replace the underlying type though so we retain the wrapped non-null/list modifiers
                    type = type.replacingUnderlyingType(with: key.firstUppercased)
                    declsInProtocol.append(.associatedtype(
                        name: type.underlyingName,
                        inherits: nestedFragProto.conformance.name
                    ))
                }
                declsInProtocol.append(
                    .let(name: key, type: genType(for: type), accessor: .get())
                )
            case .whereClause(let fragProto):
                // Some other fragment protocol that we're conforming to is
                // already declaring this field, so instead constrain it with a where clause
                // protocol FooFragment: BarFragment where A: FooFragmentA { ... }
                // protocol FooFragmentA { ... }
                fragProtosToGen.append(fragProto)
                whereClauses.append(Decl.WhereClause(
                    associatedType: key.firstUppercased,
                    constraint: fragProto.conformance.name
                ))
            }
        }
        decls.append(
            .protocol(
                name: fragProto.conformance.name,
                conforms: fragProto.conformance.inherits.map(\.name),
                whereClauses: whereClauses,
                decls: declsInProtocol
            )
        )
    }
    
    return decls
}
