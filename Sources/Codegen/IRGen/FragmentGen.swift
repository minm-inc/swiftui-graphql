import SwiftSyntax
import GraphQL
import OrderedCollections
import SwiftUIGraphQL

func gen(fragment: MergedObject, named name: String, fragmentInfo: FragmentInfo, schema: GraphQLSchema) -> [Decl] {
    let following = fragment.fragmentConformances.keys.map { name in
        let obj = fragmentInfo.objects[name]!
        return (FragmentProtocolPath(fragmentName: name, fragmentObject: obj), obj)
    }
    let fragProto = FragProtoGenerator(fragmentObjectMap: fragmentInfo.objects,
                                       fragmentConformanceGraph: fragmentInfo.conformanceGraph,
                                       schema: schema)
        .gen(fragProtoFor: fragment, following: following, currentPath: FragmentProtocolPath(fragmentName: name, fragmentObject: fragment))
    return gen(fragProto: fragProto, named: name, fragmentInfo: fragmentInfo)
}

enum FragProto {
    case proto(Proto)
    case container(path: FragmentProtocolPath, fields: OrderedDictionary<String, Field>, cases: OrderedDictionary<AnyGraphQLCompositeType, Case>, conformance: ProtocolConformance)
    
    struct Proto {
        let path: FragmentProtocolPath
        let fields: OrderedDictionary<String, Field>
        let conformance: ProtocolConformance
    }
    
    enum Field {
        case variableGetter(name: String, type: any GraphQLOutputType, object: FragProto?)
        case whereClause(FragProto)
    }
    
    struct Case {
        let proto: Proto
        let type: CaseType
        enum CaseType {
            case associatedType
            case whereClause
        }
    }
    
    var conformance: ProtocolConformance {
        switch self {
        case .proto(let proto):
            return proto.conformance
        case .container(_, _, _, let conformance):
            return conformance
        }
    }
}

class FragProtoGenerator {
    let fragmentObjectMap: [String: MergedObject]
    let fragmentConformanceGraph: [FragmentProtocolPath: ProtocolConformance]
    let schema: GraphQLSchema
    
    init(fragmentObjectMap: [String: MergedObject],
         fragmentConformanceGraph: [FragmentProtocolPath: ProtocolConformance],
         schema: GraphQLSchema) {
        self.fragmentObjectMap = fragmentObjectMap
        self.fragmentConformanceGraph = fragmentConformanceGraph
        self.schema = schema
    }
    
    func gen(fragProtoFor object: MergedObject, following fragmentObjects: [(FragmentProtocolPath, MergedObject)], currentPath: FragmentProtocolPath) -> FragProto {
        
        let fragmentObjects = fragmentObjects + object.fragmentConformances.compactMap { name, conformance in
            if conformance == .unconditional {
                let obj = fragmentObjectMap[name]!
                return (FragmentProtocolPath(fragmentName: name, fragmentObject: obj), obj)
            } else {
                return nil
            }
        }
        
        let unconditionalProto = gen(protoFor: object.unconditional, following: fragmentObjects, currentPath: currentPath)
        if object.isMonomorphic {
            return .proto(unconditionalProto)
        } else {
            // If the fragment is polymorphic, then the protocol becomes a container `ContainsFooFragment`
            let cases: OrderedDictionary<AnyGraphQLCompositeType, FragProto.Case> = object.conditional.reduce(into: [:]) { acc, x in
                let (typeCondition, selection) = x
                let applicableFragmentObjects = fragmentObjects.filter {
                    schema.isSubType(abstractType: $0.1.type, maybeSubType: typeCondition.type)
                }
                let proto = gen(protoFor: selection,
                                following: applicableFragmentObjects,
                                currentPath:  currentPath.appendingTypeDiscrimination(type: typeCondition.type))
                acc[typeCondition] = FragProto.Case(
                    proto: proto,
                    type: isShadowed(type: typeCondition, in: object) ?
                            .whereClause : .associatedType
                )
            }
            return .container(path: currentPath, fields: unconditionalProto.fields, cases: cases, conformance: unconditionalProto.conformance)
        }
    }
    
    private func isShadowed(type: AnyGraphQLCompositeType, in object: MergedObject) -> Bool {
        object.fragmentConformances.contains {
           switch $0.value {
           case .unconditional:
               return fragmentObjectMap[$0.key]!.conditional.keys.contains(type)
           case .conditional:
               return false
           }
       }
    }
    
    private func gen(protoFor selection: MergedObject.Selection, following fragmentObjects: [(FragmentProtocolPath, MergedObject)], currentPath: FragmentProtocolPath) -> FragProto.Proto {
        let fields: OrderedDictionary<String, FragProto.Field> = selection.fields.reduce(into: [:]) { acc, x in
            let (key, field) = x
            let shadowed = fragmentObjects.contains { (fragPath, fragObj) in
                fragObj.selectedKeys().contains(key)
            }
            let nestedFragmentObjects: [(FragmentProtocolPath, MergedObject)] =
                fragmentObjects.compactMap { path, obj in
                    if let fieldType = field.type.underlyingType as? any GraphQLCompositeType,
                       let nestedObj = obj[key, onType: fieldType]?.nested {
                        return (path.appendingNestedObject(nestedObj, withKey: key), nestedObj)
                    } else {
                        return nil
                    }
                }
            if shadowed {
                // If it's shadowed, then instead of defining the field we instead constrain
                // the shadowing definition from the other protocol.
                if let nested = field.nested {
                    acc[key] = .whereClause(gen(
                        fragProtoFor: nested,
                        following: nestedFragmentObjects,
                        currentPath: currentPath.appendingNestedObject(nested, withKey: key)
                    ))
                }
                // If it's shadowed and it's not nested, then we don't need to define anything
            } else {
                // If it's not shadowed then we need to define it
                acc[key] = .variableGetter(
                    name: field.name.name,
                    type: field.type,
                    object: field.nested.map { object in
                        gen(fragProtoFor: object,
                            following: nestedFragmentObjects,
                            currentPath: currentPath.appendingNestedObject(object, withKey: key))
                    }
                )
            }
        }
        let protocolConformance = fragmentConformanceGraph[currentPath]!
        return FragProto.Proto(path: currentPath, fields: fields, conformance: protocolConformance)
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
        case let .proto(proto):
            // This is a bog standard fragment that will be a protocol, continue
            // on and generate the accessors for the fields below
            fields = proto.fields
        case let .container(path, fragProtoFields, cases, _):
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
                name: path.containerUnderlyingFragmentVarName,
                type: .named(path.containerEnumName, genericArguments: cases.keys.map {
                    .named($0.type.name)
                }),
                accessor: .get()
            ))
            
            for (type, `case`) in cases {
                // Put the case protocol onto the todo list
                fragProtosToGen.append(.proto(`case`.proto))
                
                switch `case`.type {
                case .associatedType:
                    declsInProtocol.append(
                        .associatedtype(name: type.type.name,
                                        inherits: `case`.proto.conformance.name)
                    )
                case .whereClause:
                    whereClauses.append(
                        Decl.WhereClause(associatedType: type.type.name,
                                         constraint: `case`.proto.conformance.name)
                    )
                }
            }
            
            // Generate the enum
            decls.append(
                .enum(
                    name: path.containerEnumName,
                    cases: cases.keys.map {
                        Decl.Case(name: $0.type.name.firstLowercased, nestedTypeName: $0.type.name)
                    } + [Decl.Case(name: "__other", nestedTypeName: nil)],
                    decls: [],
                    conforms: ["Hashable"],
                    genericParameters: cases.map { typeName, `case` in
                        Decl.GenericParameter(
                            identifier: typeName.type.name,
                            constraint: .named(
                                `case`.proto.conformance.name
                            )
                        )
                    }
                )
            )
        }
        
        // Now generate the accessor requirements for the protocol
        for (key, field) in fields {
            switch field {
            case .variableGetter(_, let type, let object):
                var swiftUIType = graphqlTypeToSwiftUIGraphQLType(type)
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
                    swiftUIType = swiftUIType.replacingUnderlyingType(with: key.firstUppercased)
                    declsInProtocol.append(.associatedtype(
                        name: swiftUIType.underlyingName,
                        inherits: nestedFragProto.conformance.name
                    ))
                }
                declsInProtocol.append(
                    .let(name: key, type: genType(for: swiftUIType), accessor: .get())
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
