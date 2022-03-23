import OrderedCollections
import SwiftUIGraphQL
func gen(resolvedSelections: [ResolvedSelection<String>]) -> Expr {
    return .array(
        resolvedSelections.map { selection in
            switch selection {
            case .field(let field):
                let fieldExpr = Expr.functionCall(
                    called: .memberAccess(member: "init"),
                    args: [
                        .named("name", .stringLiteral(field.name)),
                        .named("arguments", .dictionary(
                            field.arguments.reduce(into: [:]) {
                                $0[Expr.stringLiteral($1.key)] = genValueExpr(value: $1.value)
                            }
                        )),
                        .named("type", genTypeExpr(type: field.type)),
                        .named("selections", gen(resolvedSelections: field.selections))
                    ]
                )
                return .functionCall(
                    called: .memberAccess(member: "field"),
                    args: [.unnamed(fieldExpr)]
                )
            case let .fragment(typeCondition, selections):
                return .functionCall(
                    called: .memberAccess(member: "fragment"),
                    args: [
                        .named("typeCondition", .stringLiteral(typeCondition)),
                        .named("selections", gen(resolvedSelections: selections))
                    ]
                )
            }
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
