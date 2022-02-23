import GraphQL
import SwiftSyntax
import Collections

func generateProtocols(for fragment: FragmentDefinition, schema: GraphQLSchema, fragmentDefinitions: [FragmentDefinition]) -> [Decl] {
    let parentType = schema.getType(name: fragment.typeCondition.name.value)!
    let object = resolveFields(
        selectionSet: fragment.selectionSet,
        parentType: parentType as! GraphQLOutputType,
        schema: schema,
        fragments: fragmentDefinitions,
        expandFragments: false
    )
    return generateProtocols(
        object: object,
        named: fragment.name.value + "Fragment",
        parentType: parentType
    )
}


func generateProtocols(object: ResolvedField.Object, named: String, parentType: GraphQLNamedType) -> [Decl] {
    var protocolDecls: [Decl] = []
    var topLevelDecls: [Decl] = []
    
    var whereClauses: [Decl.WhereClause] = []
    
    protocolDecls += object.unconditional.flatMap { (fieldName, field) -> [Decl] in
        switch field {
        case let .leaf(type):
            return [.let(name: fieldName, type: declType(for: type), accessor: .get())]
        case let .nested(nestedObj):
            let underlyingType = underlyingType(nestedObj.type)
            var protocolName = named + fieldName.capitalized
            topLevelDecls += generateProtocols(
                object: nestedObj,
                named: protocolName,
                parentType: underlyingType
            )
            let associatedTypeName = fieldName.firstUppercased
            
            if !nestedObj.conditional.isEmpty {
                protocolName = "Contains" + protocolName.firstUppercased
            }
            let fieldType = replaceUnderlyingType(nestedObj.type, with: GraphQLTypeReference(associatedTypeName))
            
            let associatedTypeDecl: Decl?
            if object.anyFragmentsInHierarchyDeclareField(fieldName: fieldName) != nil {
                whereClauses.append(Decl.WhereClause(
                    associatedType: associatedTypeName,
                    constraint: protocolName
                ))
                associatedTypeDecl = nil
            } else {
                associatedTypeDecl = .associatedtype(
                    name: associatedTypeName,
                    inherits: protocolName
                )
            }
            
            return [
                associatedTypeDecl,
                .let(name: fieldName, type: declType(for: fieldType), accessor: .get())
            ].compactMap { $0 }
        }
    }
    
    let protocolName: String

    if object.conditional.isEmpty {
        protocolName = named
    } else {
        // If there are conditionals, then the protocol becomes `ContainsFooFragment`
        // and we need to add a `__fooFragment() -> FooFragment<A,B>` requirement to the protocol,
        // as well as the FooFragment<A,B> enum
        protocolName = "Contains\(named.firstUppercased)"
        
        let underlyingType = makeConditionalFragmentType(named: named, conditional: object.conditional)
        protocolDecls.append(.let(name: "__\(named.firstLowercased)", type: underlyingType, accessor: .get()))
        
        topLevelDecls.append(
            .enum(
                name: named,
                cases: generateCasesFromPossibleTypes(typeNames: object.conditional.keys),
                decls: [],
                conforms: [],
                defaultCase: Decl.Case(name: "__other", nestedTypeName: nil),
                genericParameters: object.conditional.keys.map { typeName in
                    Decl.GenericParameter(
                        identifier: typeName,
                        constraint: .named(named + typeName)
                    )
                }
            )
        )
        
        protocolDecls += object.conditional.map { typeName, object in
            let protocolName = named + typeName
            topLevelDecls += generateProtocols(
                object: object,
                named: protocolName,
                parentType: parentType
            )
            return .associatedtype(name: typeName, inherits: protocolName)
        }
    }
    
    
    var conforms: [String] = []
    if object.conditional.isEmpty {
        conforms += object.fragProtos.keys.map { $0.protocolName }
    }
    if isCacheable(type: parentType) {
        conforms.append("Cacheable")
    }
    
    return [Decl.protocol(name: protocolName, conforms: conforms, whereClauses: whereClauses, decls: protocolDecls)] + topLevelDecls
}

func makeConditionalFragmentType(named: String, conditional: OrderedDictionary<String, ResolvedField.Object>) -> DeclType {
    DeclType.named(
        named,
        genericArguments: conditional.keys.map { .named($0) }
    )
}

/**
 As nice as they would be, protocols nested inside other types are illegal in Swift.
 ``liftProtocols(outOf:)`` moves any nested protocols to the top level and renames them appropriately with scoping, renaming any references to them.
 */
func liftProtocols(outOf decl: Decl) -> [Decl] {
    func renameProtocols(from: String, to: String) -> ((Decl) -> Decl) {
        func adjustConforms(_ conforms: [String]) -> [String] {
            conforms.map { $0 == from ? to : $0 }
        }
        
        return {(decl: Decl) in
            switch decl {
            case let .struct(name, decls, conforms):
                return .struct(
                    name: name,
                    decls: decls.map(renameProtocols(from: from, to: to)),
                    conforms: adjustConforms(conforms)
                )
            case let .enum(name, cases, decls, conforms, defaultCase, genericParameters):
                return .enum(
                    name: name,
                    cases: cases,
                    decls: decls.map(renameProtocols(from: from, to: to)),
                    conforms: adjustConforms(conforms),
                    defaultCase: defaultCase,
                    genericParameters: genericParameters
                )
            default:
                return decl
            }
        }
    }
    var protocols: [Decl] = []
    var protocolRenames: [String: String] = [:]
    let newDecl: Decl
    func extractProtocols(from decls: [Decl], inSomethingNamed name: String) -> [Decl] {
        decls
            .flatMap(liftProtocols)
            .compactMap { decl in
                switch decl {
                case let .protocol(protocolName, conforms, whereClauses, decls):
                    let newName = name + protocolName.firstUppercased
                    protocols.append(.protocol(
                        name: newName,
                        conforms: conforms,
                        whereClauses: whereClauses,
                        decls: decls
                    ))
                    protocolRenames[protocolName] = newName
                    return nil
                default:
                    return decl
                }
            }.map { decl in
                protocolRenames.reduce(decl) { (acc, x) -> Decl in
                    renameProtocols(from: x.key, to: x.value)(acc)
                }
            }
    }
    switch decl {
    case let .struct(name, decls, conforms):
        newDecl = .struct(
            name: name,
            decls: extractProtocols(from: decls, inSomethingNamed: name),
            conforms: conforms
        )
    case let .enum(name, cases, decls, conforms, defaultCase, genericParameters):
        newDecl = Decl.enum(
            name: name,
            cases: cases,
            decls: extractProtocols(from: decls, inSomethingNamed: name),
            conforms: conforms,
            defaultCase: defaultCase,
            genericParameters: genericParameters
        )
    default:
        newDecl = decl
    }
    return [newDecl] + protocols
}
