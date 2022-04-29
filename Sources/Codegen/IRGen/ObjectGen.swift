import OrderedCollections
import SwiftUIGraphQL

func gen(object: MergedSelection, named name: String, typename: String, fragmentInfo: FragmentInfo) -> Decl {
    ObjectGenerator(fragmentInfo: fragmentInfo).gen(selection: object, named: name, typename: typename)
}

/// Generates the type definitions for the objects in a GraphQL response.
private class ObjectGenerator {
//    private var objectsToConvertTo: [TypePath: [(TypePath, ResolvedField.Object)]] = [:]
    
    let fragmentInfo: FragmentInfo
    init(fragmentInfo: FragmentInfo) {
        self.fragmentInfo = fragmentInfo
    }

    /// Used to keep track of what fragment paths the currently generated object is conforming to
    private var fragmentPathStack: [[FragmentPath]] = []
    private var currentFragmentPaths: [FragmentPath] { fragmentPathStack.last ?? [] }
    
    private var typenameStack: [String] = []
    
    /// Descend into a new object and keep track of what fragment path are being conformed to
    /// - Parameters:
    ///   - fragmentConformances: The names of any fragments that the new object conforms to
    ///   - name: The name of the object (typically the key) that is being descended into
    ///   - f: A callback to perform with the descended fragment path. ``fragmentPathStack`` is reset upon leaving.
    /// - Returns: The results of `f`
    private func descendFragmentPath<T, S: Sequence>(with fragmentConformances: S, in name: String, _ f: () -> T) -> T where S.Element == String {
        var newPaths = currentFragmentPaths.compactMap { path -> FragmentPath? in
            let obj = fragmentInfo.selection(for: path)
            let isRelevantFragment = obj.fields.keys.contains(name.firstLowercased) || obj.conditionals.keys.contains(name)
            if isRelevantFragment {
                var old = path
                old.nestedObjects.append(name)
                return old
            } else {
                return nil
            }
        }
        
        newPaths += fragmentConformances.map {
            FragmentPath(fragmentName: $0)
        }
        
        fragmentPathStack.append(newPaths)
        
        defer { fragmentPathStack.removeLast() }
        
        return f()
    }
    
    private let defaultCaseName = "__other"
    private let defaultTypeName = "__Other"
    
    fileprivate func gen(selection: MergedSelection, named name: String, typename: String) -> Decl {
        typenameStack.append(typename)
        defer { typenameStack.removeLast() }
        
        return descendFragmentPath(with: selection.fragmentConformances, in: name) {
            if selection.conditionals.isEmpty {
                return genStruct(name: name, fields: selection.fields)
            } else {
                return genEnum(name: name, fields: selection.fields, cases: selection.conditionals)
            }
        }
    }
    
    private func currentConformances(for fields: OrderedDictionary<String, MergedSelection.Field>) -> [String] {
        let conformances = ProtocolConformance.baseConformances(for: fields)
            + currentFragmentPaths.map { fragmentInfo.conformanceGraph[$0]! }
        return conformances.map(\.name)
    }
    
    private func genStruct(name: String, fields: OrderedDictionary<String, MergedSelection.Field>) -> Decl {
        // TODO: convert func!!!!1!
        .struct(
            name: name,
            decls: fields.flatMap { gen(field: $1, keyed: $0) }
            + [genResolvedSelectionDecl(fields: fields, cases: [:])],
            conforms: currentConformances(for: fields)
        )
    }
    
    private func genEnum(name: String, fields: OrderedDictionary<String, MergedSelection.Field>, cases: OrderedDictionary<String, MergedSelection>) -> Decl {
        var decls: [Decl] = []
        
        // The nested types for the associated values inside the cases
        decls += cases.map { typename, selection in
            gen(selection: selection, named: typename, typename: typename)
        }
        
        // The unconditional `var foo: String {}` selected as part of the interface
        decls += fields.flatMap { (key, field) -> [Decl] in
            if let nested = field.nested {
                if !nested.conditionals.isEmpty {
                    // If on this polymorphic type there is an unconditional nested object selected,
                    // we always have to generate a new type to be used in the property getter
                    // The underlying actual concrete types then need to be converted to it
                    // We could have generated a protocol for this and used an existential, but Swift's typesystem severely limits their utility
                    // For example, you can't access anything on an existentials associated type, even if it's constrained by a protocol...
                    fatalError("TODO")
                }
                return [
                    genEnumSwitchVarNested(key: key, type: field.type, cases: cases),
                    gen(selection: nested, named: name.firstUppercased, typename: field.type.underlyingName)
                ]
            } else {
                return [genEnumSwitchVarLeaf(key: key, type: field.type, cases: cases)]
            }
        }
        
        // Add the default __Other type that contains all the unconditional, shared fields
        // But clear the path stack because it isn't related to any fragments
        fragmentPathStack.append([])
        decls.append(genStruct(name: defaultTypeName, fields: fields))
        fragmentPathStack.removeLast()
        
        // Add those var __fooFragment: ContainsFooFragment<A,B> getters for polymorphic fragments
        decls += currentFragmentPaths.map {
            genEnumFragmentConversion(path: $0, cases: cases.keys)
        }
        
        decls.append(genEnumDecoderInit(cases: cases.keys))
        decls.append(genEnumEncodeFunc(cases: cases.keys))
        // This is the `let selection = ResolvedSelection(...)` bit
        decls.append(genResolvedSelectionDecl(fields: fields, cases: cases))
        
        return .enum(
            name: name,
            cases: cases.keys.map { Decl.Case(name: $0.firstLowercased, nestedTypeName: $0) },
            decls: decls,
            conforms: currentConformances(for: fields),
            defaultCase: Decl.Case(
                name: defaultCaseName,
                nestedTypeName: defaultTypeName
            ),
            genericParameters: []
        )
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
    private func genEnumSwitchVarLeaf(key: String, type: `Type`, cases: OrderedDictionary<String, MergedSelection>) -> Decl {
        .let(
            name: key,
            type: genType(for: type),
            accessor: .get(
                .`switch`(.self, cases: (cases.keys + [defaultCaseName]).map { typeConstraintName in
                        let enumName = typeConstraintName.firstLowercased
                        return .`case`(genEnumBind(enumName: enumName), [
                            .return(.identifier(enumName).access(key))
                        ])
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
    private func genEnumSwitchVarNested(key: String, type: `Type`, cases: OrderedDictionary<String, MergedSelection>) -> Decl {
        let type = genType(for: type)
        let defaultCase = Decl.Syntax.Case.`case`(genEnumBind(enumName: defaultCaseName), [
            .return(.identifier(defaultCaseName))
        ])
        return .let(
            name: key,
            type: type,
            accessor: .get(.`switch`(.self, cases: [defaultCase] + cases.keys.map { typename in
                let enumName = typename.firstLowercased
                let returns = map(
                    type: type,
                    base: .identifier(enumName).access(key)) {
                        $0.access("convert").call()
                    }
                return .`case`(genEnumBind(enumName: enumName), [
                    .return(returns)
                ])
            }))
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
    private func genEnumFragmentConversion(path: FragmentPath, cases: OrderedSet<String>) -> Decl {
        .let(
            name: "__\(path.fullyQualifiedName.firstLowercased)",
            type: fragmentInfo.makeUnderlyingFragmentEnumType(path: path),
            accessor: .get(
                .`switch`(.self, cases: cases.map(\.firstLowercased).map { enumName in
                    let returns: Expr
                    var matchExpr = Expr.dot(enumName)
                    let fragmentPathObj = fragmentInfo.selection(for: path)
                    if !fragmentPathObj.conditionals.keys.contains(enumName.firstUppercased) {
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
            )
        )
    }
    
    private func genEnumDecoderInit(cases: OrderedSet<String>) -> Decl {
        .`init`(
            parameters: [Decl.Parameter("from", "decoder", type: .named("Decoder"))],
            throws: .throws,
            body: [
                .decl(
                    .`let`(
                        name: "container",
                        initializer: .`try`(
                            .identifier("decoder").access("container").call(
                                .named("keyedBy", .identifier("TypenameCodingKeys").access("self"))
                            )
                        )
                    )
                ),
                .decl(
                    .`let`(
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
                    cases: cases.map { typename in
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
    
    private func genEnumEncodeFunc(cases: OrderedSet<String>) -> Decl {
        .func(
            name: "encode",
            parameters: [Decl.Parameter("to", "encoder", type: .named("Encoder"))],
            throws: .throws,
            body: [.switch(.`self`, cases: cases.union([defaultCaseName]).map { typename in
                    .`case`(.dot(typename.firstLowercased).call(.unnamed(.letPattern(typename.firstLowercased))), [
                        .expr(.`try`(
                            .identifier(typename.firstLowercased).access("encode").call(
                                .named("to", .identifier("encoder"))
                            )
                        ))
                    ])
            })]
        )
    }
    

    /// Generates a `let foo: Foo` struct variable with corresponding nested object definition if needed
    private func gen(field: MergedSelection.Field, keyed key: String) -> [Decl] {
        if let nested = field.nested {
            let renamedType = field.type.replacingUnderlyingType(with: key.firstUppercased)
            return [
                .let(name: key, type: genType(for: renamedType)),
                gen(selection: nested, named: key.firstUppercased, typename: field.type.underlyingName)
            ]
        } else {
            let isTypename = field.name == "__typename"
            return [.let(
                name: key,
                type: genType(for: field.type),
                initializer: isTypename ? .stringLiteral(typenameStack.last!) : nil,
                accessor: isTypename ? .var : .let
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
