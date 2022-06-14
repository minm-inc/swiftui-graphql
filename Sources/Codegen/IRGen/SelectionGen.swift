import OrderedCollections
import SwiftUIGraphQL

func genResolvedSelectionDecl(fields: OrderedDictionary<String, MergedObject.Selection.Field>, cases: OrderedSet<AnyGraphQLCompositeType>) -> Decl {
    .`let`(
        name: "selection",
        type: .named("ResolvedSelection", genericArguments: [.named("String")]),
        initializer: Expr.functionCall(
            called: .identifier("ResolvedSelection"),
            args: [
                .named("fields", gen(dictForFields: fields)),
                .named("conditional", .dictionary(
                    cases.map(\.type.name).reduce(into: [:]) { acc, x in
                        acc[.stringLiteral(x)] = .identifier(x.firstUppercased)
                            .access("selection")
                            .access("fields")
                    }
                ))
            ]
        ),
        isStatic: true,
        access: .public
    )
}

private func gen(dictForFields fields: OrderedDictionary<String, MergedObject.Selection.Field>) -> Expr {
    .dictionary(
        fields.reduce(into: [:]) { acc, x in
            let (key, field) = x
            let nestedExpr: Expr
            if field.nested != nil {
                nestedExpr = .identifier(key.firstUppercased).access("selection")
            } else {
                nestedExpr = .nilLiteral
            }
            acc[.stringLiteral(key)] = .functionCall(
                called: .memberAccess(member: "init"),
                args: [
                    .named("name", .stringLiteral(field.name.name)),
                    .named("arguments", .dictionary(
                        field.arguments.reduce(into: [:]) {
                            $0[Expr.stringLiteral($1.key)] = genValueExpr(value: $1.value)
                        }
                    )),
                    .named("type", genTypeExpr(type: graphqlTypeToSwiftUIGraphQLType(field.type))),
                    .named("nested", nestedExpr)
                ]
            )
        }
    )
}

private func genValueExpr(value: NonConstValue) -> Expr {
    switch value {
    case let .variable(x):
        return .functionCall(
            called: .memberAccess(member: "variable"),
            args: [.unnamed(.stringLiteral(x))]
        )
    case .null:
        return .memberAccess(member: "null")
    case let .int(x):
        return .functionCall(
            called: .memberAccess(member: "int"),
            args: [.unnamed(.intLiteral(x))]
        )
    case let .float(x):
        return .functionCall(
            called: .memberAccess(member: "float"),
            args: [.unnamed(.floatLiteral(x))]
        )
    case let .boolean(x):
        return .functionCall(
            called: .memberAccess(member: "boolean"),
            args: [.unnamed(.boolLiteral(x))]
        )
    case let .string(x):
        return .functionCall(
            called: .memberAccess(member: "string"),
            args: [.unnamed(.stringLiteral(x))]
        )
    case let .enum(x):
        return .functionCall(
            called: .memberAccess(member: "enum"),
            args: [.unnamed(.stringLiteral(x))]
        )
    case let .list(xs):
        return .functionCall(
            called: .memberAccess(member: "list"),
            args: [.unnamed(.array(xs.map(genValueExpr)))]
        )
    case .object:
        fatalError("Can't generate an object Expr")
    }
}

private func genTypeExpr(type: `Type`) -> Expr {
    switch type {
    case let .nonNull(x):
        return .functionCall(
            called: .memberAccess(member: "nonNull", base: "`Type`"),
            args: [.unnamed(genNonNullTypeExpr(type: x))]
        )
    case let .list(x):
        return .functionCall(
            called: .memberAccess(member: "list", base: "`Type`"),
            args: [.unnamed(genTypeExpr(type: x))]
        )
    case let .named(x):
        return .functionCall(
            called: .memberAccess(member: "named", base: "`Type`"),
            args: [.unnamed(.stringLiteral(x))]
        )
    }
}

private func genNonNullTypeExpr(type: NonNullType) -> Expr {
    switch type {
    case let .named(x):
        return .functionCall(
            called: .memberAccess(member: "named", base: "NonNullType"),
            args: [.unnamed(.stringLiteral(x))]
        )
    case let .nonNull(x):
        return .functionCall(
            called: .memberAccess(member: "nonNull", base: "NonNullType"),
            args: [.unnamed(genTypeExpr(type: x))]
        )
    }
}
