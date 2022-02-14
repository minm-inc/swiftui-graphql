//
//  QueryCodegen.swift
//  
//
//  Created by Luke Lau on 07/12/2021.
//

import Foundation
import SwiftSyntax
import GraphQL
import Collections

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
    var object = resolveFields(
        selectionSet: operation.selectionSet,
        parentType: operationRootType(for: operation.operation, schema: schema),
        schema: schema,
        fragments: fragments
    )
    
    for fragment in fragments {
        object = attachFragProtos(to: object, fragment: fragment, schema: schema, fragments: fragments)
    }
    
    if !object.conditional.isEmpty { fatalError("A conditional fragment on the root query? Weird") }
    
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
            decls: variableDecls,
            conforms: ["Encodable", "Equatable"]
        )
    }
    let fragmentMap = fragments.reduce(into: [:]) { $0[$1.name.value] = $1 }
    let fragmentsString = allUsedFragments(in: operation.selectionSet, fragments: fragmentMap).sorted().map { fragmentName in
        fragmentMap[fragmentName]!.printed
    }.joined(separator: "\n")
    let queryString = operation.printed + "\n" + fragmentsString + "\n"
    
    let queryStrDecl = Decl.staticLetString(name: "query", literal: queryString)
    
    let structDecl = genTypeDefintion(
        for: object,
        named: (operation.name?.value.firstUppercased ?? "Anonymous") + operationSuffix(for: operation.operation),
        schema: schema
    )
    guard case let .struct(name, decls, conforms) = structDecl else {
        fatalError()
    }
    return .struct(
        name: name,
        decls: decls + [queryStrDecl, variablesStruct].compactMap { $0 },
        conforms: ["Queryable"] + conforms
    )
}


private func genDecls(for fieldMap: ResolvedFieldMap, parentType: GraphQLNamedType, schema: GraphQLSchema) -> [Decl] {
    fieldMap.flatMap { (name, field) -> [Decl] in
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
        case let .nested(object):
            let renamedType = replaceUnderlyingType(object.type, with: try! GraphQLObjectType(name: name.firstUppercased, fields: [:]))
            return [
                Decl.let(name: name, type: declType(for: renamedType)),
                genTypeDefintion(
                    for: object,
                    named: name,
                    schema: schema
                )
            ]
        }
    }
}

private func genTypeDefintion(for object: ResolvedField.Object, named: String, schema: GraphQLSchema) -> Decl {
    let type = underlyingType(object.type)
    var conforms = ["Codable"]
    if isCachable(type: type) {
        conforms.append("Identifiable")
    }
    
    if object.conditional.isEmpty {
        // If there are no conditional fields, we want to generate a straight up struct.
        return Decl.struct(
            name: named.firstUppercased,
            decls: genDecls(for: object.unconditional, parentType: type, schema: schema),
            conforms: conforms + object.fragProtos.keys.map { $0.protocolName }
        )
    } else {
        // If there are conditional fields, then we'll need to generate an enum with nested structs inside them.
        return genConditionalEnum(
            type: type,
            schema: schema,
            object: object,
            named: named.firstUppercased,
            conforms: conforms
        )
    }
}

private func genConditionalEnum(type: GraphQLNamedType, schema: GraphQLSchema, object: ResolvedField.Object, named: String, conforms: [String]) -> Decl {
    
    var decls: [Decl] = object.conditional.map { typeConstraintName, conditionalObject in

        let unconditional = mergeResolvedFieldMaps(object.unconditional, conditionalObject.unconditional)
        // TODO: Some of the nested fields may conform to the protocols we define in this enum
        
        let object = ResolvedField.Object(
            type: conditionalObject.type,
            unconditional: unconditional,
            conditional: conditionalObject.conditional,
            fragProtos: conditionalObject.fragProtos
        )
        return genTypeDefintion(for: object, named: typeConstraintName, schema: schema)
    }
    
    let defaultCaseName = "__other"
    
    let defaultDecl = Decl.struct(
        name: defaultCaseName.capitalized,
        decls: genDecls(for: object.unconditional, parentType: type, schema: schema),
        conforms: ["Codable"]
    )
    
    decls.append(defaultDecl)
    
    func genEnumSwitchVar(name: String, type: GraphQLOutputType) -> Decl {
        .let(
            name: name,
            type: declType(for: type),
            defaultValue: nil,
            isVar: true,
            getter: Decl.Syntax.returnSwitch(
                expr: ExprSyntax(IdentifierExprSyntax {
                    $0.useIdentifier(SyntaxFactory.makeSelfKeyword())
                }),
                cases: (object.conditional.keys + [defaultCaseName]).map { typeConstraintName in
                    let enumName = typeConstraintName.firstLowercased
                    return Decl.Syntax.SwitchCase(
                        enumName: enumName,
                        binds: [enumName],
                        returns: .memberAccess(member: name, base: .identifier(enumName))
                    )
                }
            )
        )
    }
    
    // The unconditional `var foo: String {}` selected as part of the interface
    decls += object.unconditional.flatMap { (name, field) -> [Decl] in
        switch field {
        case let .leaf(type):
            return [genEnumSwitchVar(name: name, type: type)]
        case let .nested(object):
            return [
                genEnumSwitchVar(name: name, type: object.type)
            ] + generateProtocols(object: object, named: name.firstUppercased, parentType: underlyingType(object.type))
        }
    }
    
    var allConforms = conforms
    
    //TODO: fill back in
    for (fragQuali, protoInfo) in object.fragProtos.filter({ $0.value.isConditional }) {
        // TODO: Only need this if it's a *conditional fragment*
        allConforms.append("Contains" + fragQuali.protocolName)
        decls.append(
            .let(name: "__\(fragQuali.protocolName.firstLowercased)",
                 type: makeConditionalFragmentType(named: fragQuali.protocolName, conditional: object.conditional),
                 defaultValue: nil,
                 isVar: true,
                 getter: .returnSwitch(
                    expr: ExprSyntax(IdentifierExprSyntax {
                        $0.useIdentifier(SyntaxFactory.makeSelfKeyword())
                    }),
                    cases: object.conditional.keys.map { $0.firstLowercased }.map { typeConstraintName in
                        Decl.Syntax.SwitchCase(
                            enumName: typeConstraintName,
                            binds: [typeConstraintName],
                            returns: .functionCall(
                                called: .memberAccess(member: typeConstraintName),
                                args: [.identifier(typeConstraintName)]
                            )
                        )
                    } + [Decl.Syntax.SwitchCase(enumName: "__other", binds: [], returns: .memberAccess(member: "__other"))]
                )
            )
        )
    }
    
    return Decl.enum(
        name: named,
        cases: generateCasesFromPossibleTypes(typeNames: object.conditional.keys),
        decls: decls,
        conforms: allConforms,
        defaultCase: Decl.Case(
            name: defaultCaseName,
            nestedTypeName: defaultCaseName.capitalized
        ),
        genericParameters: []
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
    ).map(swiftGen.gen)
}

private func makeConditionalFragmentType(named: String, conditional: OrderedDictionary<String, ResolvedField.Object>) -> DeclType {
    DeclType.named(
        named,
        genericArguments: conditional.keys.map { .named($0) }
    )
}

func generateProtocols(object: ResolvedField.Object, named: String, parentType: GraphQLNamedType) -> [Decl] {

    
//    let conformingFragmentAssociatedTypes = object.fragmentConformances.map {
//        
//    }
//    
//    var whereClauses: OrderedDictionary<String, String> = [:]
    var protocolDecls: [Decl] = []
    var topLevelDecls: [Decl] = []
    
    var whereClauses: [Decl.WhereClause] = []
    
    protocolDecls += object.unconditional.flatMap { (fieldName, field) -> [Decl] in
        switch field {
        case let .leaf(type):
            return [.protocolVar(name: fieldName, type: declType(for: type))]
        case let .nested(nestedObj):
            let underlyingType = underlyingType(nestedObj.type)
            let protocolName = named + fieldName.capitalized
            topLevelDecls += generateProtocols(
                object: nestedObj,
                named: protocolName,
                parentType: underlyingType
            )
            let associatedTypeName = fieldName.capitalized
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
                .protocolVar(name: fieldName, type: declType(for: fieldType))
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
        protocolDecls.append(.protocolVar(name: "__\(named.firstLowercased)", type: underlyingType))
        
        topLevelDecls.append(
            .enum(
                name: named,
                cases: generateCasesFromPossibleTypes(typeNames: object.conditional.keys),
                decls: [],
                conforms: isCachable(type: parentType) ? ["Identifiable"] : [],
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
    
    let conforms: [String]
    if object.conditional.isEmpty {
        conforms = object.fragProtos.keys.map { $0.protocolName }
    } else {
        conforms = []
    }
    
    return [Decl.protocol(name: protocolName, conforms: conforms, whereClauses: whereClauses, decls: protocolDecls)] + topLevelDecls
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
    case `struct`(name: String, decls: [Decl], conforms: [String])
    case `enum`(
        name: String,
        cases: [Case],
        decls: [Decl],
        conforms: [String],
        defaultCase: Case?,
        genericParameters: [GenericParameter]
    )
    case `let`(name: String, type: DeclType, defaultValue: ExprSyntax? = nil, isVar: Bool = false, getter: Syntax? = nil)
    case staticLetString(name: String, literal: String)
    case `protocol`(name: String, conforms: [String], whereClauses: [WhereClause], decls: [Decl])
    // TODO: Merge with `let`
    case protocolVar(name: String, type: DeclType)
    case `associatedtype`(name: String, inherits: String)
    case `func`(name: String, returnType: DeclType, body: Syntax?)
    
    enum Syntax: Equatable {
        case returnSwitch(expr: ExprSyntax, cases: [SwitchCase])
        /** A case statement like `case .enumName(let binds...)`*/
        struct SwitchCase: Equatable {
            let enumName: String
            let binds: [String]
            let returns: Expr
        }
    }
    
    struct WhereClause: Equatable {
        let associatedType: String
        let constraint: String
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

indirect enum Expr: Equatable, ExpressibleByStringLiteral {
    /** `Base.member` */
    case memberAccess(member: String, base: Expr? = nil)
    /** `called(args)` */
    case functionCall(called: Expr, args: [Expr] = [])
    /** `identifier` */
    case identifier(String)
    
    init(stringLiteral value: StringLiteralType) {
        self = .identifier(value)
    }
}

indirect enum DeclType: Equatable {
    case named(String, genericArguments: [DeclType] = [])
    case array(DeclType)
    case optional(DeclType)
}

/** Generates a map of `caseName` to `TypeName`, given a bunch of names of types */
private func generateCasesFromPossibleTypes<T: Sequence>(typeNames: T) -> [Decl.Case] where T.Element == String {
    typeNames.map { Decl.Case(name: $0.firstLowercased, nestedTypeName: $0) }
}
