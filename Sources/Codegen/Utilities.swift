import GraphQL

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

func replaceUnderlyingType(_ type: GraphQLType, with newType: GraphQLType) -> GraphQLType {
    switch type {
    case let type as GraphQLList:
        return GraphQLList(replaceUnderlyingType(type.ofType, with: newType))
    case let type as GraphQLNonNull:
        return GraphQLNonNull(replaceUnderlyingType(type.ofType, with: newType) as! GraphQLNullableType)
    default:
        return newType
    }
}

func operationRootType(for type: OperationType, schema: GraphQLSchema) -> GraphQLObjectType {
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
