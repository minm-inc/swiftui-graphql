import GraphQL
import Collections

func genOperation(_ operation: OperationDefinition, schema: GraphQLSchema, fragmentDefinitions: [FragmentDefinition]) -> Decl {
    var object = resolveFields(
        selectionSet: operation.selectionSet,
        parentType: operationRootType(for: operation.operation, schema: schema),
        schema: schema,
        fragments: fragmentDefinitions
    )
    for fragment in fragmentDefinitions {
        object = attachFragProtos(to: object, fragment: fragment, schema: schema, fragments: fragmentDefinitions)
    }

    let variablesStruct: Decl?
    if operation.variableDefinitions.isEmpty {
        variablesStruct = nil
    } else {
        let variableDecls = operation.variableDefinitions.map { varDef -> Decl in
            let type = typeFromAST(schema: schema, inputTypeAST: varDef.type)!
            return Decl.`let`(
                name: varDef.variable.name.value,
                type: declType(for: type),
                initializer: varDef.defaultValue.map(convertToExpr)
            )
        }
        variablesStruct = .struct(
            name: "Variables",
            decls: variableDecls,
            conforms: ["Encodable", "Equatable"]
        )
    }
    let fragmentMap = fragmentDefinitions.reduce(into: [:]) { $0[$1.name.value] = $1 }
    let fragmentsString = allUsedFragments(in: operation.selectionSet, fragments: fragmentMap).sorted().map { fragmentName in
        fragmentMap[fragmentName]!.printed
    }.joined(separator: "\n")
    let queryString = operation.printed + "\n" + fragmentsString + "\n"
    
    let queryStrDecl = Decl.staticLetString(name: "query", literal: queryString)
    
    let generator = StructGenerator(schema: schema)
    let structDecl = generator.genTypeDefintion(
        for: object,
        named: (operation.name?.value.firstUppercased ?? "Anonymous") + operationSuffix(for: operation.operation)
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

private class StructGenerator {
    let schema: GraphQLSchema
    init(schema: GraphQLSchema) {
        self.schema = schema
    }
    
    typealias TypePath = [String]
    private var typePath: TypePath = []
    private var objectsToConvertTo: [TypePath: [(TypePath, ResolvedField.Object)]] = [:]
    
    private func genDecls(for fieldMap: ResolvedFieldMap, parentType: GraphQLNamedType, generateTypeDefs: Bool = true) -> [Decl] {
        fieldMap.flatMap { (name, field) -> [Decl] in
            switch field {
            case let .leaf(type):
                let isTypename = name == "__typename"
                return [Decl.let(
                    name: name,
                    type: declType(for: type),
                    initializer: isTypename ? .stringLiteral(parentType.name) : nil,
                    accessor: isTypename ? .var : .let
                )]
            case let .nested(object):
                let renamedType = replaceUnderlyingType(object.type, with: try! GraphQLObjectType(name: name.firstUppercased, fields: [:]))
                let letDecl = Decl.let(name: name, type: declType(for: renamedType))
                
                if generateTypeDefs {
                    return [
                        letDecl,
                        genTypeDefintion(for: object, named: name)
                    ]
                } else {
                    return [letDecl]
                }
            }
        }
    }

    func genTypeDefintion(for object: ResolvedField.Object, named: String) -> Decl {
        typePath.append(named.firstUppercased)
        defer { typePath.removeLast() }
        
        let type = underlyingType(object.type)
        var conforms = ["Codable"]
        if isCacheable(type: type) {
            conforms.append("Cacheable")
        }
        
        if object.conditional.isEmpty {
            var extraDecls: [Decl] = []
            while let (toTypePath, objectToConvertTo) = self.objectsToConvertTo[typePath]?.popLast() {
                extraDecls.append(makeConvertFunc(type: toTypePath, fromObject: object, toObject: objectToConvertTo))
            }
            // If there are no conditional fields, we want to generate a straight up struct.
            return Decl.struct(
                name: named.firstUppercased,
                decls: genDecls(for: object.unconditional, parentType: type) + extraDecls,
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
    
    private let defaultCaseName = "__other"
    private let defaultTypeName = "__Other"

    private func genConditionalEnum(type: GraphQLNamedType, schema: GraphQLSchema, object: ResolvedField.Object, named: String, conforms: [String]) -> Decl {
        
        var decls: [Decl] = []
        
        
        // The unconditional `var foo: String {}` selected as part of the interface
        decls += object.unconditional.flatMap { (name, field) -> [Decl] in
            switch field {
            case let .leaf(type):
                return [genEnumSwitchVarLeaf(name: name, type: type)]
            case let .nested(nestedObj):
                // If on this polymorphic type there is an unconditional nested object selected,
                // we always have to generate a new type to be used in the property getter
                // The underlying actual concrete types then need to be converted to it
                // We could have generated a protocol for this and used an existential, but Swift's typesystem severely limits their utility
                // For example, you can't access anything on an existentials associated type, even if it's constrained by a protocol...
                for (conditionalTypeName, condObj) in object.conditional {
                    guard case .nested(let fromObj) = condObj.unconditional[name] else {
                        fatalError()
                    }
                    addObjectsToConvertTo(
                        fromTypePath: typePath + [conditionalTypeName, name.firstUppercased],
                        toTypePath: typePath + [name.firstUppercased],
                        fromObject: fromObj,
                        toObject: nestedObj
                    )
                }
                return [
                    genEnumSwitchVarNested(fieldName: name, type: nestedObj.type),
                    genTypeDefintion(for: nestedObj, named: name)
                ]
            }
        }
        
        // Generate the types for the associated values inside the enum cases
        let nestedTypeDecls = object.conditional.map { genTypeDefintion(for: $1, named: $0) }
        decls.insert(contentsOf: nestedTypeDecls, at: 0)
        
        let defaultDecl = Decl.struct(
            name: defaultTypeName,
            decls: genDecls(for: object.unconditional, parentType: type, generateTypeDefs: false),
            conforms: ["Codable"]
        )
        
        decls.append(defaultDecl)
        
        /// A simple
        ///
        ///```swift
        ///  var b: Int? {
        ///     switch self {
        ///     case .impl(let impl):
        ///         return impl.b
        ///     case .__other(let __other):
        ///         return __other.b
        ///     }
        /// }
        /// ```
        func genEnumSwitchVarLeaf(name: String, type: GraphQLOutputType) -> Decl {
            .let(
                name: name,
                type: declType(for: type),
                accessor: .get(
                    Decl.Syntax.returnSwitch(
                        expr: .self,
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
            )
        }
        
        /// A tortured
        ///
        ///```swift
        ///  var b: B? {
        ///     switch self {
        ///     case .impl(let impl):
        ///         return impl.b.map({ $0.convert() })
        ///     case .__other(let __other):
        ///         return __other.b.map({ $0.convert() })
        ///     }
        /// }
        /// ```
        func genEnumSwitchVarNested(fieldName: String, type: GraphQLOutputType) -> Decl {
            let type = declType(for: type)
            return .let(
                name: fieldName,
                type: type,
                accessor: .get(Decl.Syntax.returnSwitch(
                    expr: .self,
                    cases: object.conditional.keys.map { typeConstraintName in
                        let enumName = typeConstraintName.firstLowercased
                        let returns = map(
                            type: type,
                            base: .memberAccess(member: fieldName, base: .identifier(enumName))) {
                                .functionCall(called: .memberAccess(member: "convert", base: $0))
                            }
                        return Decl.Syntax.SwitchCase(
                            enumName: enumName,
                            binds: [enumName],
                            returns: returns
                        )
                    } + [
                        Decl.Syntax.SwitchCase(
                            enumName: defaultCaseName,
                            binds: [defaultCaseName],
                            returns: .memberAccess(
                                member: fieldName,
                                base: .identifier(defaultCaseName)
                            )
                        )
                    ]
                ))
            )
        }

        
        var allConforms = conforms
        
        for fragQuali in object.fragProtos.filter({ $0.value.isConditional }).keys {
            allConforms.append("Contains" + fragQuali.protocolName)
            decls.append(
                .let(name: "__\(fragQuali.protocolName.firstLowercased)",
                     type: makeConditionalFragmentType(named: fragQuali.protocolName, conditional: object.conditional),
                     accessor: .get(.returnSwitch(
                        expr: .self,
                        cases: object.conditional.keys.map { $0.firstLowercased }.map { typeConstraintName in
                            Decl.Syntax.SwitchCase(
                                enumName: typeConstraintName,
                                binds: [typeConstraintName],
                                returns: .functionCall(
                                    called: .memberAccess(member: typeConstraintName),
                                    args: [.unnamed(.identifier(typeConstraintName))]
                                )
                            )
                        } + [Decl.Syntax.SwitchCase(
                            enumName: defaultCaseName,
                            binds: [],
                            returns: .memberAccess(member: defaultCaseName)
                        )]
                    ))
                )
            )
        }
        
        while let (toTypePath, objectToConvertTo) = self.objectsToConvertTo[typePath]?.popLast() {
            decls.append(makeConvertFunc(type: toTypePath, fromObject: object, toObject: objectToConvertTo))
        }
        
        return Decl.enum(
            name: named,
            cases: generateCasesFromPossibleTypes(typeNames: object.conditional.keys),
            decls: decls,
            conforms: allConforms,
            defaultCase: Decl.Case(
                name: defaultCaseName,
                nestedTypeName: defaultTypeName
            ),
            genericParameters: []
        )
    }
    
    private func addObjectsToConvertTo(fromTypePath: TypePath, toTypePath: TypePath, fromObject: ResolvedField.Object, toObject: ResolvedField.Object) {
        objectsToConvertTo.merge(
            [fromTypePath: [(toTypePath, toObject)]],
            uniquingKeysWith: +
        )
        func recurse(fromTypePath: TypePath, toTypePath: TypePath, fromObject: ResolvedField.Object, toObject: ResolvedField.Object) {
            for (fieldName, field) in fromObject.unconditional {
                switch field {
                case .nested(let nestedFromObj):
                    guard case .nested(let nestedToObj) = toObject.unconditional[fieldName] else {
                        fatalError("Mismatching objects")
                    }
                    let fromTypePath = fromTypePath + [fieldName.firstUppercased]
                    let toTypePath = toTypePath + [fieldName.firstUppercased]
                    addObjectsToConvertTo(
                        fromTypePath: fromTypePath,
                        toTypePath: toTypePath,
                        fromObject: nestedFromObj,
                        toObject: nestedToObj
                    )
                default:
                    break
                }
            }
            for (conditionalType, conditionalFromObj) in fromObject.conditional {
                let newToTypePath: TypePath
                if (toObject.conditional.isEmpty) {
                    newToTypePath = toTypePath
                } else {
                    newToTypePath = toTypePath + [conditionalType]
                }
                recurse(
                    fromTypePath: fromTypePath + [conditionalType],
                    toTypePath: newToTypePath,
                    fromObject: conditionalFromObj,
                    toObject: toObject
                )
            }
        }
        recurse(fromTypePath: fromTypePath, toTypePath: toTypePath, fromObject: fromObject, toObject: toObject)
    }


    /// Given a type that may be wrapped in an array or optional, add maps to the ``Expr`` until it is safely mapped over
    func map(type: DeclType, base: Expr, _ f: (Expr) -> Expr) -> Expr {
        switch type {
        case .array(let type), .optional(let type):
            return .functionCall(
                called: .memberAccess(
                    member: "map",
                    base: base
                ),
                args: [.unnamed(.closure(
                    map(type: type, base: .anonymousIdentifier(0), f)
                ))]
            )
        default:
            return f(base)
        }
    }

    private func makeConvertFunc(type: TypePath, fromObject: ResolvedField.Object, toObject: ResolvedField.Object) -> Decl {
        let initializer = type.suffix(from: 1).reduce(Expr.identifier(type.first!)) { acc, x in
                .memberAccess(member: x, base: acc)
        }
        let returnType = type.suffix(from: 1).reduce(DeclType.named(type.first!)) { acc, x in
                .memberType(x, acc)
        }
        let body: Decl.Syntax
        
        func makeArgs(base: ((String) -> Expr)) -> [Expr.Arg] {
            toObject.unconditional.map { fieldName, field in
                switch field {
                case .leaf:
                    return .named(fieldName, .identifier(fieldName))
                case .nested(let object):
                    let expr = map(
                        type: declType(for: object.type),
                        base: base(fieldName)
                    ) {
                        .functionCall(called: .memberAccess(member: "convert", base: $0))
                    }
                    return .named(fieldName, expr)
                }
            }
        }
        
        if !fromObject.conditional.isEmpty {
            body = .returnSwitch(expr: .`self`, cases: (fromObject.conditional.keys + [defaultCaseName]).map { conditionalType in
                let bindName = conditionalType.firstLowercased
                
                let args = makeArgs {
                    Expr.memberAccess(member: $0, base: .identifier(bindName))
                }
                return Decl.Syntax.SwitchCase(
                    enumName: conditionalType.firstLowercased,
                    binds: [bindName],
                    returns: .functionCall(called: initializer, args: args)
                )
            })
        } else {
            if toObject.conditional.isEmpty {
                // We're converting to a struct
                let args = makeArgs { .identifier($0) }
                body = .expr(.functionCall(called: initializer, args: args))
            } else {
                // We're converting to an enum
                fatalError("TODO")
            }
        }
        return .func(
            name: "convert",
            returnType: returnType,
            body: body,
            access: .fileprivate
        )
    }

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

/** Generates a map of `caseName` to `TypeName`, given a bunch of names of types */
func generateCasesFromPossibleTypes<T: Sequence>(typeNames: T) -> [Decl.Case] where T.Element == String {
    typeNames.map { Decl.Case(name: $0.firstLowercased, nestedTypeName: $0) }
}
