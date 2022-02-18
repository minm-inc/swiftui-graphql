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
