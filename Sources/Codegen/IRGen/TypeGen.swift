import GraphQL

func declType(for graphqlType: GraphQLType) -> DeclType {
    func go(type: GraphQLType, addOptional: Bool) -> DeclType {
        func wrapOptional(_ x: DeclType) -> DeclType {
            if addOptional {
                return .optional(x)
            } else {
                return x
            }
        }
        
        switch type {
        case let type as GraphQLList:
            return wrapOptional(
                .array(go(type: type.ofType, addOptional: true))
            )
        case let type as GraphQLNonNull:
            return go(type: type.ofType, addOptional: false)
        case let type as GraphQLNamedType:
            let name: String
            if type.name == "Boolean" {
                name = "Bool"
            } else {
                name = type.name
            }
            return wrapOptional(.named(name))
        default:
            fatalError("Don't know how to handle this type")
        }
    }
    return go(type: graphqlType, addOptional: true)
}
