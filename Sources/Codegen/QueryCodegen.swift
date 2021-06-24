//
//  QueryCodegen.swift
//  
//
//  Created by Luke Lau on 07/12/2021.
//

import Foundation
import SwiftSyntax
import GraphQL

func generateStruct(for operation: OperationDefinition, schema: GraphQLSchema, fragments: [FragmentDefinition], queryString: String) -> DeclSyntax {
    SwiftGen().gen(decl:
        generateStruct(
           for: operation,
           schema: schema,
           fragments: fragments,
           queryString: queryString
        )
    )
}

func generateStruct(for operation: OperationDefinition, schema: GraphQLSchema, fragments: [FragmentDefinition], queryString: String) -> Decl {
    func genDataDecl(for type: GraphQLNamedType, unconditional: ResolvedFieldMap, conditional: [String: ResolvedFieldMap], fragmentConformances: Set<String>) -> Decl {
        var conforms = ["Codable"]
        if isCachable(type: type) {
            conforms.append("Identifiable")
        }
        conforms += fragmentConformances
        
        if conditional.isEmpty {
            // If there are no conditional fields, we want to generate a straight up struct.
            return Decl.struct(
                name: type.name, // TODO: handle the case where there's an alias and so duplicate structs
                defs: genDecls(for: unconditional, parentType: type),
                conforms: conforms
            )
        } else {
            // If there are conditional fields, then we'll need to generate an enum with nested structs inside them.
            
            var decls: [Decl] = conditional.map { typeConstraintName, conditionalFields in
                genDataDecl(
                    for: schema.getType(name: typeConstraintName)!,
                    unconditional: mergeResolvedFieldMaps(unconditional, conditionalFields),
                    conditional: [:],
                       fragmentConformances: Set(fragmentConformances.map { $0 + typeConstraintName })
                )
            }
            
            let defaultCaseName = "other"
            
            let defaultDecl = Decl.struct(
                name: defaultCaseName.capitalized,
                defs: genDecls(for: unconditional, parentType: type),
                conforms: conforms
            )
            
            decls.append(defaultDecl)
            
            func generateProtocolVar(name: String, type: GraphQLOutputType) -> Decl {
                .let(
                    name: name,
                    type: declType(for: type),
                    defaultValue: nil,
                    isVar: true,
                    getter: Decl.Syntax.returnSwitch(
                        expr: ExprSyntax(IdentifierExprSyntax {
                            $0.useIdentifier(SyntaxFactory.makeSelfKeyword())
                        }),
                        cases: (conditional.keys + [defaultCaseName]).reduce(into: [:]) { acc, typeConstraintName in
                            acc[typeConstraintName.lowercased()] = name
                        }
                    )
                )
            }
            
            // The unconditional `var foo: String {}` selected as part of the interface
            decls += unconditional.flatMap { (name, field) -> [Decl] in
                switch field {
                case let .leaf(type):
                    return [generateProtocolVar(name: name, type: type)]
                case let .nested(type, unconditional, conditional, fragmentConformances):
                    return [
                        generateProtocolVar(name: name, type: type),
                        Decl.let(name: name, type: declType(for: type)),
                        genDataDecl(
                            for: underlyingType(type),
                            unconditional: unconditional,
                            conditional: conditional,
                            fragmentConformances: fragmentConformances
                        )
                    ]
                }
            }
            
            return Decl.enum(
                name: type.name, // TODO: Handle the case where there's an alias and so duplicate enums
                cases: generateCasesFromPossibleTypes(typeNames: conditional.keys),
                defs: decls,
                conforms: conforms,
                defaultCase: Decl.Case(
                    name: defaultCaseName,
                    nestedTypeName: defaultCaseName.capitalized
                ),
                genericParameters: []
            )
        }
        
//        switch underlyingType(type) {
//        case let objectType as GraphQLObjectType:
//            var conforms = ["Codable"]
//            if isCachable(type: objectType) {
//                conforms.append("Identifiable")
//            }
//            conforms += fragmentConformances
//
//            if !conditional.isEmpty {
//                fatalError("Objects shouldn't have any conditional conformances, they will always conform")
//            }
//
//            let structName = objectType.name // TODO: handle the case where there's an alias and so duplicate structs
//            return Decl.struct(
//                name: structName,
//                defs: genDecls(for: unconditional, parentType: objectType),
//                conforms: conforms
//            )
//        case let interfaceType as GraphQLInterfaceType:
//            if conditional.isEmpty {
//                // TODO: Generate a struct here
//                fatalError("TODO: This should generate a struct")
//            }
//            var conforms = ["Codable"]
//            if isCachable(type: interfaceType) {
//                conforms.append("Identifiable")
//            }
//
//            var decls: [Decl] = conditional.map { typeConstraintName, conditionalFields in
//                genDataDecl(
//                    for: schema.getType(name: typeConstraintName)!,
//                    unconditional: mergeResolvedFieldMaps(unconditional, conditionalFields),
//                    conditional: [:],
//                    fragmentConformances: fragmentConformances
//                )
//            }
//
//            let defaultCaseName = "other"
//
//            let defaultDecl = Decl.struct(
//                name: defaultCaseName.capitalized,
//                defs: genDecls(for: unconditional, parentType: interfaceType),
//                conforms: conforms
//            )
//
//            decls.append(defaultDecl)
//
//            func generateProtocolVar(name: String, type: GraphQLOutputType) -> Decl {
//                .let(
//                    name: name,
//                    type: declType(for: type),
//                    defaultValue: nil,
//                    isVar: true,
//                    getter: Decl.Syntax.returnSwitch(
//                        expr: ExprSyntax(IdentifierExprSyntax {
//                            $0.useIdentifier(SyntaxFactory.makeSelfKeyword())
//                        }),
//                        cases: (conditional.keys + [defaultCaseName]).reduce(into: [:]) { acc, typeConstraintName in
//                            acc[typeConstraintName.lowercased()] = name
//                        }
//                    )
//                )
//            }
//
//            // The unconditional `var foo: String {}` selected as part of the interface
//            decls += unconditional.flatMap { (name, field) -> [Decl] in
//                switch field {
//                case let .leaf(type):
//                    return [generateProtocolVar(name: name, type: type)]
//                case let .nested(type, unconditional, conditional, fragmentConformances):
//                    return [
//                        generateProtocolVar(name: name, type: type),
//                        Decl.let(name: name, type: declType(for: type)),
//                        genDataDecl(for: type, unconditional: unconditional, conditional: conditional, fragmentConformances: fragmentConformances)
//                    ]
//                }
//            }
//
//            return Decl.enum(
//                name: interfaceType.name, // TODO: Handle the case where there's an alias and so duplicate enums
//                cases: generateCaseNameTypeNameMap(typeNames: conditional.keys),
//                defs: decls,
//                conforms: conforms,
//                defaultCaseName: defaultCaseName
//            )
//        case let unionType as GraphQLUnionType:
//            let nestedDecls: [Decl] = unionType.types.compactMap { type in
//                if let nestedFields = conditional[type.name] {
//                    return genDataDecl(
//                        for: type,
//                        unconditional: nestedFields,
//                        conditional: [:],
//                        fragmentConformances: fragmentConformances
//                    )
//                } else {
//                    return nil
//                }
//            }
//
//            return Decl.enum(
//                name: unionType.name, // TODO: Handle the case where there's an alias and so duplicate enums
//                cases: generateCaseNameTypeNameMap(typeNames: unionType.types.map { $0.name }),
//                defs: nestedDecls,
//                conforms: ["Codable"],
//                defaultCaseName: nil
//            )
//        default:
//            fatalError()
//        }
    }
    
    func genDecls(for fields: ResolvedFieldMap, parentType: GraphQLNamedType) -> [Decl] {
        fields.flatMap { (name, field) -> [Decl] in
            switch field {
            case let .leaf(type):
                let defaultValue: ExprSyntax?
                let isTypename = name == "__typename"
                if isTypename {
                    defaultValue = genStringLiteral(string: parentType.name)
                } else {
                    defaultValue = nil
                }
                return [Decl.let(
                    name: name,
                    type: declType(for: type),
                    defaultValue: defaultValue,
                    isVar: isTypename
                )]
            case let .nested(type, unconditional, conditional, fragmentConformances):
                return [
                    Decl.let(name: name, type: declType(for: type)),
                    genDataDecl(
                        for: underlyingType(type),
                        unconditional: unconditional,
                        conditional: conditional,
                        fragmentConformances: fragmentConformances
                    )
                ]
            }
        }
    }
    
    let (unconditional, conditional, conformances) = resolveFields(
        selectionSet: operation.selectionSet,
        parentType: operationRootType(for: operation.operation, schema: schema),
        schema: schema,
        fragments: fragments
    )
    
    if !conditional.isEmpty { fatalError("A conditional fragment on the root query? Weird") }
    
    let variablesStruct: Decl?
    if operation.variableDefinitions.isEmpty {
        variablesStruct = nil
    } else {
        let variableDecls = operation.variableDefinitions.map { varDef -> Decl in
            let type = typeFromAST(schema: schema, inputTypeAST: varDef.type)!
            let defaultValueSyntax: ExprSyntax?
            if let defaultValue = varDef.defaultValue {
                defaultValueSyntax = exprSyntax(for: defaultValue)
            } else {
                defaultValueSyntax = nil
            }
            return Decl.`let`(
                name: varDef.variable.name.value,
                type: declType(for: type),
                defaultValue: defaultValueSyntax
            )
        }
        variablesStruct = .struct(
            name: "Variables",
            defs: variableDecls,
            conforms: ["Encodable", "Equatable"]
        )
    }
    let fragmentMap = fragments.reduce(into: [:]) { $0[$1.name.value] = $1 }
    let fragmentsString = allUsedFragments(in: operation.selectionSet, fragments: fragmentMap).map { fragmentName in
        fragmentMap[fragmentName]!.printed
    }.joined(separator: "\n")
    let queryString = operation.printed + "\n" + fragmentsString + "\n"
    
    let queryStrDecl = Decl.staticLetString(name: "query", literal: queryString)
    
    let decls = genDecls(for: unconditional, parentType: schema.queryType)
                + [queryStrDecl, variablesStruct].compactMap { $0 }
    return Decl.struct(
        name: (operation.name?.value.firstUppercased ?? "Anonymous") + operationSuffix(for: operation.operation),
        defs: decls,
        conforms: ["Queryable", "Codable"] + conformances
    )
}

private func allUsedFragments(in selectionSet: SelectionSet, fragments: [String: FragmentDefinition]) -> Set<String> {
    selectionSet.selections.reduce([]) { acc, selection in
        switch selection {
        case let .field(field):
            if let selectionSet = field.selectionSet {
                return acc.union(allUsedFragments(in: selectionSet, fragments: fragments))
            }
            return acc
        case let .fragmentSpread(fragmentSpread):
            let fragment = fragments[fragmentSpread.name.value]!
            return acc.union([fragment.name.value]).union(allUsedFragments(in: fragment.selectionSet, fragments: fragments))
        case let .inlineFragment(inlineFragment):
            return acc.union(allUsedFragments(in: inlineFragment.selectionSet, fragments: fragments))
        }
    }
}

private func operationSuffix(for type: OperationType) -> String {
    switch type {
    case .query:
        return "Query"
    case .mutation:
        return "Mutation"
    case .subscription:
        return "Subscription"
    }
}

private func operationRootType(for type: OperationType, schema: GraphQLSchema) -> GraphQLObjectType {
    switch type {
    case .query:
        return schema.queryType
    case .mutation:
        guard let mutationType = schema.mutationType else {
            fatalError("Schema has no mutation type")
        }
        return mutationType
    case .subscription:
        guard let subscriptionType = schema.subscriptionType else {
            fatalError("Schema has no subscription type")
        }
        return subscriptionType
    }
}


func underlyingType(_ type: GraphQLType) -> GraphQLNamedType {
    if let type = type as? GraphQLList {
        return underlyingType(type.ofType)
    } else if let type = type as? GraphQLNonNull {
        return underlyingType(type.ofType)
    } else if let type = type as? GraphQLNamedType {
        return type
    } else {
        fatalError("Don't understand how to get the underlying type of \(type)")
    }
}

func generateProtocols(for fragment: FragmentDefinition, schema: GraphQLSchema, fragmentDefinitions: [FragmentDefinition]) -> [DeclSyntax] {
    
    let parentType = schema.getType(name: fragment.typeCondition.name.value)!
    let swiftGen = SwiftGen()
    let (unconditional, conditional, _) = resolveFields(
        selectionSet: fragment.selectionSet,
        parentType: parentType,
        schema: schema,
        fragments: fragmentDefinitions
    )
    return generateProtocols(
        unconditional: unconditional,
        conditional: conditional,
        named: fragment.name.value + "Fragment",
        parentType: parentType
    ).map(swiftGen.gen)
}

func generateProtocols(unconditional: ResolvedFieldMap, conditional: [String: ResolvedFieldMap], named: String, parentType: GraphQLNamedType) -> [Decl] {

    var protocolDecls: [Decl] = []
    var topLevelDecls: [Decl] = []
    if !conditional.isEmpty {
        // If there are conditionals, then we need to add a `__underlying() -> FragmentNameUnderlying<A,B>` requirement to the protocol,
        // as well as the FragmentNameUnderlying<A,B> enum
        
        let underlyingEnumName = named + "Underlying"
        let underlyingType = DeclType.named(
            underlyingEnumName,
            genericArguments: conditional.keys.map { .named($0) }
        )
        protocolDecls.append(
            .func(
                name: "__underlying",
                returnType: underlyingType,
                body: nil
            )
        )
        
        topLevelDecls.append(
            .enum(
                name: underlyingEnumName,
                cases: generateCasesFromPossibleTypes(typeNames: conditional.keys),
                defs: [],
                conforms: ["Codable"] + (isCachable(type: parentType) ? ["Identifiable"] : []),
                defaultCase: Decl.Case(name: "__other", nestedTypeName: nil),
                genericParameters: conditional.keys.map { typeName in
                    Decl.GenericParameter(
                        identifier: typeName,
                        constraint: .named(named + typeName)
                    )
                }
            )
        )
        
        protocolDecls += conditional.map { typeName, fieldMap in
            let protocolName = named + typeName
            topLevelDecls += generateProtocols(
                unconditional: fieldMap,
                conditional: [:],
                named: protocolName,
                parentType: parentType
            )
            return .associatedtype(name: typeName, inherits: protocolName)
        }
    }
    protocolDecls += unconditional.flatMap { (fieldName, field) -> [Decl] in
        switch field {
        case let .leaf(type):
            return [.protocolVar(name: fieldName, type: declType(for: type))]
        case let .nested(type, unconditional, conditional, _):
            let underlyingType = underlyingType(type)
            let protocolName = named + fieldName.capitalized
            topLevelDecls += generateProtocols(
                unconditional: unconditional,
                conditional: conditional,
                named: protocolName,
                parentType: underlyingType
            )
            let associatedTypeName = fieldName.capitalized
            let fieldType = replaceUnderlyingType(type, with: GraphQLTypeReference(associatedTypeName))
            return [
                .associatedtype(
                    name: associatedTypeName,
                    inherits: protocolName
                ),
                .protocolVar(name: fieldName, type: declType(for: fieldType))
            ]
        }
    }
    
    return [Decl.protocol(name: named, conforms: ["Codable"], decls: protocolDecls)] + topLevelDecls
}

private func replaceUnderlyingType(_ type: GraphQLType, with newType: GraphQLType) -> GraphQLType {
    switch type {
    case let type as GraphQLList:
        return GraphQLList(replaceUnderlyingType(type.ofType, with: newType))
    case let type as GraphQLNonNull:
        return GraphQLNonNull(replaceUnderlyingType(type.ofType, with: newType) as! GraphQLNullableType)
    default:
        return newType
    }
}

/// Because SwiftSyntax's AST is quite hefty, we use a mini AST that more succintly represents what we're trying to generate
///
/// For the ease of testing, it's generic over the representation of types: That is, either a ``GraphQLType`` or a ``TypeSyntax``.
/// It can be converted to the latter form via ``convertTypes``
enum Decl: Equatable {
    case `struct`(name: String, defs: [Decl], conforms: [String])
    case `enum`(
        name: String,
        cases: [Case],
        defs: [Decl],
        conforms: [String],
        defaultCase: Case?,
        genericParameters: [GenericParameter]
    )
    case `let`(name: String, type: DeclType, defaultValue: ExprSyntax? = nil, isVar: Bool = false, getter: Syntax? = nil)
    case staticLetString(name: String, literal: String)
    case `protocol`(name: String, conforms: [String], decls: [Decl])
    // TODO: Merge with `let`
    case protocolVar(name: String, type: DeclType)
    case `associatedtype`(name: String, inherits: String)
    case `func`(name: String, returnType: DeclType, body: Syntax?)
    
    enum Syntax: Equatable {
        case returnSwitch(expr: ExprSyntax, cases: [String: String])
    }
    
    struct GenericParameter: Equatable {
        let identifier: String
        let constraint: DeclType
    }
    
    struct Case: Equatable {
        let name: String
        let nestedTypeName: String?
    }
}

indirect enum DeclType: Equatable {
    case named(String, genericArguments: [DeclType] = [])
    case array(DeclType)
    case optional(DeclType)
}

/** Generates a map of `caseName` to `TypeName`, given a bunch of names of types */
private func generateCasesFromPossibleTypes<T: Sequence>(typeNames: T) -> [Decl.Case] where T.Element == String {
    typeNames.map { Decl.Case(name: $0.lowercased(), nestedTypeName: $0) }
}
