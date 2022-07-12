import OrderedCollections
import GraphQL
import SwiftUIGraphQL

func gen(object: MergedObject, named name: String, type: any GraphQLCompositeType, fragmentInfo: FragmentInfo, schema: GraphQLSchema) -> Decl {
    ObjectGenerator(fragmentInfo: fragmentInfo, schema: schema)
        .gen(object: object, key: name, type: type)
}

/// Generates the type definitions for the objects in a GraphQL response.
private class ObjectGenerator {
//    private var objectsToConvertTo: [TypePath: [(TypePath, ResolvedField.Object)]] = [:]
    
    let fragmentInfo: FragmentInfo
    let schema: GraphQLSchema
    init(fragmentInfo: FragmentInfo, schema: GraphQLSchema) {
        self.fragmentInfo = fragmentInfo
        self.schema = schema
    }

    /// Used to keep track of what fragment paths the currently generated object is conforming to
    private var fragmentPathStack: [[FragmentProtocolPath]] = []
    private var currentFragmentPaths: [FragmentProtocolPath] {
        fragmentPathStack.last ?? []
    }
    
    private var typeStack: [any GraphQLCompositeType] = []
    
    /// A stack of the currently objects currently being generated
    private var objectStack: [MergedObject] = []

    private enum DescendType {
        case nestedObject(key: String)
        case typeDiscrimination(any GraphQLCompositeType)
    }
    
    /// Descend into a new object and keep track of what fragment path are being conformed to
    /// - Parameters:
    ///   - type: Information about the type of descent we're doing: Are we going down into another GraphQL object, or creating a nested Swift type to discriminate between GraphQL types?
    ///   - f: A callback to perform with the descended fragment path. ``fragmentPathStack`` is reset upon leaving.
    /// - Returns: The results of `f`
    private func descendFragmentPath<T>(descent: DescendType, _ f: () -> T) -> T {
        guard let currentObject = objectStack.last else {
            fatalError("Can't descendwithout being inside an object first")
        }
        
        // First update the existing FragmentPaths that we are following from parent objects and add another nested object to them
        var newPaths: [FragmentProtocolPath] = currentFragmentPaths
            // Only continue updating these FragmentPaths if their fragments contain this field the object represents
            .filter {
                switch descent {
                case .nestedObject(let key):
                    return fragmentInfo.selection(for: $0).fields.keys.contains(key)
                case .typeDiscrimination(let type):
                    return fragmentInfo.object(for: $0).conditional.keys.contains(AnyGraphQLCompositeType(type))
                }
            }.map {
                switch descent {
                case .nestedObject(let key):
                    return $0.appendingNestedObject(currentObject, withKey: key)
                case .typeDiscrimination(let type):
                    return $0.appendingTypeDiscrimination(type: type)
                }
            }
        
        // Collect the fragments that this object will conform to
        let newFragmentConformances = currentObject.fragmentConformances.filter { _, conformance in
            switch descent {
            // TODO: Conditional fragment conformances
            case .nestedObject:
                return conformance == .unconditional
            case .typeDiscrimination(let type):
                if case .conditional(let typeCondition) = conformance {
                    return schema.isSubType(abstractType: typeCondition, maybeSubType: type)
                } else {
                    return true
                }
            }
        }.keys
        
        // Then begin tracking said new fragments
        newPaths += newFragmentConformances.map { name in
            let path = FragmentProtocolPath(fragmentName: name, fragmentObject: fragmentInfo.objects[name]!)
            
            // Shortcut the container fragment if this is a new nested object, that so
            // happens to meet the type requirement of a polymorphic fragment
            if case .nestedObject = descent,
               schema.isSubType(abstractType: fragmentInfo.objects[name]!.type,
                                maybeSubType: currentObject.type),
               path.isContainer {
                let newPath = path.appendingTypeDiscrimination(type: currentObject.type)
                if fragmentInfo.conformanceGraph[newPath] != nil {
                    return newPath
                }
                return path
            } else {
                return path
            }
        }.filter {
            // If we're in a type discrimination, even though this selection technically conforms
            // to the fragment, the container is already conforming to it, so don't conform to it in
            // the type discrimination here.
            if case .typeDiscrimination = descent, $0.isContainer {
                return false
            } else {
                return true
            }
        }
        
        fragmentPathStack.append(newPaths)
        
        defer { fragmentPathStack.removeLast() }
        
        return f()
    }
    
    
    private let defaultCaseName = "__other"
    private let defaultTypeName = "__Other"
    
    /// Generates a ``Decl`` for the ```MergedObject`` in the current context.
    /// - Parameters:
    ///   - object: The object to generate a Swift type declaration for.
    ///   - key: The key for the field that the object is being generated for: This is used to pick a name for the type and bookkeep the current fragment protocols it should conform to.
    ///   - typename: The name of the object's GraphQL type.
    /// - Returns: A Swift ``Decl`` that defines a concrete type for the ``MergedObject``.
    fileprivate func gen(object: MergedObject, key: String, type: any GraphQLCompositeType) -> Decl {
        typeStack.append(type)
        objectStack.append(object)
        defer {
            typeStack.removeLast()
            objectStack.removeLast()
        }
        
        return descendFragmentPath(descent: .nestedObject(key: key)) {
            if object.isMonomorphic {
                return genStruct(name: key.firstUppercased, fields: object.unconditional.fields)
            } else {
                return genEnum(name: key.firstUppercased, fields: object.unconditional.fields, cases: object.conditional)
            }
        }
    }
    
    private func currentConformances(for fields: OrderedDictionary<String, MergedObject.Selection.Field>) -> [String] {
        let conformances = ProtocolConformance.baseConformances(for: fields)
            + currentFragmentPaths.map { fragmentInfo.conformanceGraph[$0]! }
        return conformances.map(\.name)
    }
    
    private func genStruct(name: String, fields: OrderedDictionary<String, MergedObject.Selection.Field>) -> Decl {
        // TODO: convert func!!!!1!
        .struct(
            name: name,
            decls: fields.flatMap { gen(field: $1, keyed: $0) }
            + [genResolvedSelectionDecl(fields: fields, cases: []),
               genStructInitializer(fields: fields)],
            conforms: currentConformances(for: fields)
        )
    }
    
    private func genStructInitializer(fields: OrderedDictionary<String, MergedObject.Selection.Field>) -> Decl {
        let fieldTypes: OrderedDictionary<String, DeclType> = fields.filter { $0.key != "__typename" }.reduce(into: [:]) { acc, x in
            // Nested types are named after their key
            if x.value.nested != nil {
                let type = graphqlTypeToSwiftUIGraphQLType(x.value.type).replacingUnderlyingType(with: x.key.firstUppercased)
                acc[x.key] = genType(for: type)
            } else {
                acc[x.key] = genType(for: graphqlTypeToSwiftUIGraphQLType(x.value.type))
            }
        }
        return .`init`(
            parameters: fieldTypes.map { Decl.Parameter($0, type: $1) },
            body: fieldTypes.keys.map { .assignment(lhs: .`self`.access($0), rhs: .identifier($0)) }
        )
    }
    
    private func genEnum(name: String, fields: OrderedDictionary<String, MergedObject.Selection.Field>, cases: OrderedDictionary<AnyGraphQLCompositeType, MergedObject.Selection>) -> Decl {
        var decls: [Decl] = []
        
        // The nested types for the associated values inside the cases
        decls += cases.map { type, selection in
            typeStack.append(type.type)
            defer { typeStack.removeLast() }
            return descendFragmentPath(descent: .typeDiscrimination(type.type)) {
                genStruct(name: type.type.name, fields: selection.fields)
            }
        }
        
        // The unconditional `var foo: String {}` selected as part of the interface
        decls += fields.flatMap { (key, field) -> [Decl] in
            if let nested = field.nested {
                if !nested.isMonomorphic {
                    // If on this polymorphic type there is an unconditional nested object selected,
                    // we always have to generate a new type to be used in the property getter
                    // The underlying actual concrete types then need to be converted to it
                    // We could have generated a protocol for this and used an existential, but Swift's typesystem severely limits their utility
                    // For example, you can't access anything on an existentials associated type, even if it's constrained by a protocol...
                    fatalError("TODO")
                }
                return [
                    genEnumSwitchVarNested(key: key, type: field.type as! any GraphQLCompositeType, cases: cases.keys),
                    gen(object: nested, key: key, type: underlyingType(field.type) as! any GraphQLCompositeType)
                ]
            } else {
                return [genEnumSwitchVarLeaf(key: key, type: field.type, cases: cases.keys)]
            }
        }
        
        // Add the default __Other type that contains all the unconditional, shared fields
        // But clear the path stack because it isn't related to any fragments
        fragmentPathStack.append([])
        decls.append(genStruct(name: defaultTypeName, fields: fields))
        fragmentPathStack.removeLast()
        
        // Add those var __fooFragment: ContainsFooFragment<A,B> getters for polymorphic fragments
        decls += OrderedSet(currentFragmentPaths.flatMap(allAncestorFragments(path:))).map {
            genEnumFragmentConversion(path: $0, cases: cases.keys)
        }
        
        decls.append(genEnumDecoderInit(cases: cases.keys))
        decls.append(genEnumEncodeFunc(cases: cases.keys))
        // This is the `let selection = ResolvedSelection(...)` bit
        decls.append(genResolvedSelectionDecl(fields: fields, cases: cases.keys))
        
        return .enum(
            name: name,
            cases: cases.keys.map {
                Decl.Case(name: $0.type.name.firstLowercased, nestedTypeName: $0.type.name)
            } + [Decl.Case(name: defaultCaseName, nestedTypeName: defaultTypeName)],
            decls: decls,
            conforms: currentConformances(for: fields),
            genericParameters: []
        )
    }
    
    /// Given a fragment path, returns that fragment path plus any other fragment paths that it conforms to
    private func allAncestorFragments(path: FragmentProtocolPath) -> [FragmentProtocolPath] {
        [path] + fragmentInfo.conformanceGraph[path]!.ancestors.compactMap {
            switch $0.type {
            case .fragment(let path): return path
            case .plain: return nil
            }
        }
    }
    
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
    private func genEnumSwitchVarLeaf(key: String, type: any GraphQLOutputType, cases: OrderedSet<AnyGraphQLCompositeType>) -> Decl {
        .let(
            name: key,
            type: genType(for: type),
            accessor: .get(
                .`switch`(.self, cases: (cases.map(\.type.name) + [defaultCaseName]).map { typeConstraintName in
                        let enumName = typeConstraintName.firstLowercased
                        return .`case`(genEnumBind(enumName: enumName), [
                            .return(.identifier(enumName).access(key))
                        ])
                    }
                )
            ),
            access: .public
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
    private func genEnumSwitchVarNested(key: String, type: any GraphQLCompositeType, cases: OrderedSet<AnyGraphQLCompositeType>) -> Decl {
        let type = genType(for: type)
        let defaultCase = Decl.Syntax.Case.`case`(genEnumBind(enumName: defaultCaseName), [
            .return(.identifier(defaultCaseName))
        ])
        return .let(
            name: key,
            type: type,
            accessor: .get(.`switch`(.self, cases: [defaultCase] + cases.map(\.type).map { caseType in
                let enumName = caseType.name.firstLowercased
                let returns = map(
                    type: type,
                    base: .identifier(enumName).access(key)) {
                        $0.access("convert").call()
                    }
                return .`case`(genEnumBind(enumName: enumName), [
                    .return(returns)
                ])
            })),
            access: .public
        )
    }
    
    /// Generates a `.foo(let foo)` pattern matching expression
    private func genEnumBind(enumName: String) -> Expr {
        .dot(enumName).call(.unnamed(.letPattern(enumName)))
    }
            
//            accessor: .get(Decl.Syntax.returnSwitch(
//                expr: .self,
//                cases: cases.keys.map { typeConstraintName in
//                    let enumName = typeConstraintName.firstLowercased
//                    let returns = map(
//                        type: type,
//                        base: .identifier(enumName).access(key)) {
//                            $0.access("convert").call()
//                        }
//                    return Decl.Syntax.SwitchCase(
//                        enumName: enumName,
//                        binds: [.named(enumName)],
//                        returns: returns
//                    )
//                } + [
//                    Decl.Syntax.SwitchCase(
//                        enumName: defaultCaseName,
//                        binds: [.named(defaultCaseName)],
//                        returns: .identifier(defaultCaseName).access(key)
//                    )
//                ]
//            ))
//        )
//    }
    
    /// Generates those `__fooFragment` computed variables in enums for converting them to the correct fragment type
    private func genEnumFragmentConversion(path: FragmentProtocolPath, cases: OrderedSet<AnyGraphQLCompositeType>) -> Decl {
        .let(
            name: path.containerUnderlyingFragmentVarName,
            type: fragmentInfo.makeUnderlyingFragmentEnumType(path: path),
            accessor: .get(
                .`switch`(.self, cases: cases.map(\.type).map { type in
                    let returns: Expr
                    let enumName = type.name.firstLowercased
                    var matchExpr = Expr.dot(enumName)
                    let fragmentPathObj = fragmentInfo.object(for: path)
                    if !fragmentPathObj.conditional.keys.contains(AnyGraphQLCompositeType(type)) {
                        returns = .memberAccess(member: defaultCaseName)
                    } else {
                        returns = .functionCall(
                            called: .dot(enumName),
                            args: [.unnamed(.identifier(enumName))]
                        )
                        matchExpr = matchExpr.call(.unnamed(.letPattern(enumName)))
                    }
                    return .`case`(matchExpr, [.return(returns)])
                } + [.`case`(.dot(defaultCaseName), [.return(.dot(defaultCaseName))])])
            ),
            access: .public
        )
    }
    
    private func genEnumDecoderInit(cases: OrderedSet<AnyGraphQLCompositeType>) -> Decl {
        .`init`(
            parameters: [Decl.Parameter("from", "decoder", type: .named("Decoder"))],
            throws: .throws,
            body: [
                .decl(
                    .let(
                        name: "container",
                        initializer: .`try`(
                            .identifier("decoder").access("container").call(
                                .named("keyedBy", .identifier("TypenameCodingKeys").access("self"))
                            )
                        )
                    )
                ),
                .decl(
                    .let(
                        name: "typename",
                        initializer: .`try`(
                            .identifier("container").access("decode").call(
                                .unnamed(.identifier("String").access("self")),
                                .named("forKey", .memberAccess(member: "__typename"))
                            )
                        )
                    )
                ),
                .`switch`(
                    .identifier("typename"),
                    cases: cases.map(\.type.name).map { typename in
                        .`case`(.stringLiteral(typename), [
                            .`assignment`(
                                lhs: .`self`,
                                rhs: .memberAccess(member: typename.firstLowercased)
                                    .call(.unnamed(.`try`(
                                        .identifier(typename)
                                        .call(.named("from", .identifier("decoder")))
                                    )))
                            )
                        ])
                    } + [.`default`([
                        .`assignment`(
                            lhs: .`self`,
                            rhs: .memberAccess(member: defaultCaseName)
                                .call(.unnamed(.`try`(
                                    .identifier(defaultTypeName).call(.named("from", .identifier("decoder")))
                                )))
                        )
                    ])]
                )
            ]
        )
    }
    
    private func genEnumEncodeFunc(cases: OrderedSet<AnyGraphQLCompositeType>) -> Decl {
        .func(
            name: "encode",
            parameters: [Decl.Parameter("to", "encoder", type: .named("Encoder"))],
            throws: .throws,
            body: [.switch(.`self`, cases: (cases.map(\.type.name) + [defaultCaseName]).map { typename in
                    .`case`(.dot(typename.firstLowercased).call(.unnamed(.letPattern(typename.firstLowercased))), [
                        .expr(.`try`(
                            .identifier(typename.firstLowercased).access("encode").call(
                                .named("to", .identifier("encoder"))
                            )
                        ))
                    ])
            })],
            access: .public
        )
    }
    

    /// Generates a `let foo: Foo` struct variable with corresponding nested object definition if needed
    private func gen(field: MergedObject.Selection.Field, keyed key: String) -> [Decl] {
        if let nested = field.nested {
            let renamedType = graphqlTypeToSwiftUIGraphQLType(field.type).replacingUnderlyingType(with: key.firstUppercased)
            return [
                .let(name: key, type: genType(for: renamedType), access: .public),
                gen(object: nested, key: key, type: field.type.underlyingType as! (any GraphQLCompositeType))
            ]
        } else {
            let isTypename = field.name == "__typename"
            return [.let(
                name: key,
                type: genType(for: field.type),
                initializer: isTypename ? .stringLiteral(typeStack.last!.name) : nil,
                accessor: isTypename ? .var : .let,
                access: .public
            )]
        }
    }
    
    /// Given a type that may be wrapped in an array or optional, add maps to the ``Expr`` until it is safely mapped over
    private func map(type: DeclType, base: Expr, _ f: (Expr) -> Expr) -> Expr {
        switch type {
        case .array(let type), .optional(let type):
            return base.access("map").call(.unnamed(.closure(
                map(type: type, base: .anonymousIdentifier(0), f)
            )))
        default:
            return f(base)
        }
    }
}
