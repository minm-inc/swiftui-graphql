import GraphQL

func convertToExpr(_ value: Value) -> Expr {
    switch value {
    case let .booleanValue(booleanValue):
        return .boolLiteral(booleanValue.value)
    case let .stringValue(stringValue):
        return .stringLiteral(stringValue.value)
    default:
        fatalError("TODO")
    }
}

/// This converts a ``Value`` into an ``Expr`` for the **equivalent SwiftUIGraphQL constructor**.
///
/// i.e. `.boolean(true)` will get converted into
/// ```swift
/// .functionCall(called: .memberAccess(member: "bool"), args: [.boolLiteral(true)])
/// ```
/// If you want to just convert it to an ``Expr``, use ``convertToExpr(_:)``
func genValueExpr(_ value: Value) -> Expr {
    let constructor: String, innerExpr: Expr
    switch value {
    case let .variable(variable):
        constructor = "variable"
        innerExpr = .stringLiteral(variable.name.value)
    case let .booleanValue(booleanValue):
        constructor = "bool"
        innerExpr = .boolLiteral(booleanValue.value)
    case let .stringValue(x):
        constructor = "string"
        innerExpr = .stringLiteral(x.value)
    case let .intValue(x):
        constructor = "int"
        innerExpr = .intLiteral(Int(x.value)!)
    default:
        fatalError("TODO")
    }
    return .functionCall(
        called: .memberAccess(member: constructor),
        args: [.unnamed(innerExpr)]
    )
}
