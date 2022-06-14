import GraphQL
import OrderedCollections
import SwiftUIGraphQL

extension GraphQLType {
    var underlyingType: any GraphQLNamedType {
        Codegen.underlyingType(self)
    }
}

func underlyingType(_ type: any GraphQLType) -> any GraphQLNamedType {
    if let type = type as? GraphQLList {
        return underlyingType(type.ofType)
    } else if let type = type as? GraphQLNonNull {
        return underlyingType(type.ofType)
    } else if let type = type as? (any GraphQLNamedType) {
        return type
    } else {
        fatalError("Don't understand how to get the underlying type of \(type)")
    }
}

func replaceUnderlyingType(_ type: any GraphQLType, with newType: any GraphQLType) -> any GraphQLType {
    switch type {
    case let type as GraphQLList:
        return GraphQLList(replaceUnderlyingType(type.ofType, with: newType))
    case let type as GraphQLNonNull:
        return GraphQLNonNull(replaceUnderlyingType(type.ofType, with: newType) as! (any GraphQLNullableType))
    default:
        return newType
    }
}

func operationRootType(for type: GraphQL.OperationType, schema: GraphQLSchema) -> GraphQLObjectType {
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



/// The base protocol conformances that an object with the given set of fields will conform to
extension SwiftUIGraphQL.`Type` {
    var underlyingName: String {
        switch self {
        case .nonNull(let type): return type.underlyingName
        case .list(let type): return type.underlyingName
        case .named(let name): return name
        }
    }
    
    func replacingUnderlyingType(with newTypeName: String) -> SwiftUIGraphQL.`Type` {
        switch self {
        case .named:
            return .named(newTypeName)
        case .list(let type):
            return .list(type.replacingUnderlyingType(with: newTypeName))
        case .nonNull(let type):
            return .nonNull(type.replacingUnderlyingType(with: newTypeName))
        }
    }
}

extension SwiftUIGraphQL.NonNullType {
    var underlyingName: String {
        switch self {
        case .named(let name): return name
        case .nonNull(let type): return type.underlyingName
        }
    }
    
    func replacingUnderlyingType(with newTypeName: String) -> SwiftUIGraphQL.NonNullType {
        switch self {
        case .named:
            return .named(newTypeName)
        case .nonNull(let type):
            return .nonNull(type.replacingUnderlyingType(with: newTypeName))
        }
    }
}

extension String {
    var firstUppercased: String { prefix(1).uppercased() + dropFirst() }
    var firstLowercased: String { prefix(1).lowercased() + dropFirst() }
}

/// A not-so-type-erasing wrapper that allows us to use `any GraphQLCompositeType` as a key in a dictionary etc.
class AnyGraphQLCompositeType: Hashable {
    let type: any GraphQLCompositeType
    init(_ x: any GraphQLCompositeType) {
        self.type = x
    }
    
    func hash(into hasher: inout Hasher) {
        type.hash(into: &hasher)
    }
    
    static func == (lhs: AnyGraphQLCompositeType, rhs: AnyGraphQLCompositeType) -> Bool {
        lhs.type === rhs.type
    }
}
