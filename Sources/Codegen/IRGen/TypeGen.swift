import GraphQL
import SwiftUIGraphQL

func genType(for graphqlType: GraphQLType) -> DeclType {
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
            if let scalar = type as? GraphQLScalarType {
                return wrapOptional(.named(genTypeName(forScalar: scalar)))
            } else {
                return wrapOptional(.named(type.name))
            }
        default:
            fatalError("Don't know how to handle this type")
        }
    }
    return go(type: graphqlType, addOptional: true)
}

func genType(for type: SwiftUIGraphQL.`Type`) -> DeclType {
    func go(type: SwiftUIGraphQL.`Type`, addOptional: Bool) -> DeclType {
        func wrapOptional(_ x: DeclType) -> DeclType {
            if addOptional {
                return .optional(x)
            } else {
                return x
            }
        }
        switch type {
        case .list(let type):
            return wrapOptional(
                .array(go(type: type, addOptional: true))
            )
        case .nonNull(let type):
            return go(type: type)
        case .named(let name):
            return wrapOptional(.named(name))
        }
    }
    func go(type: SwiftUIGraphQL.NonNullType) -> DeclType {
        switch type {
        case .named(let name):
            return .named(name)
        case .nonNull(let type):
            return go(type: type, addOptional: false)
        }
    }
    return go(type: type, addOptional: true)
}


func graphqlTypeToSwiftUIGraphQLType(_ type: GraphQLType) -> SwiftUIGraphQL.`Type` {
    switch type {
    case let type as GraphQLNamedType:
        if let scalar = type as? GraphQLScalarType {
            return .named(genTypeName(forScalar: scalar))
        } else {
            return .named(type.name)
        }
    case let type as GraphQLList:
        return .list(graphqlTypeToSwiftUIGraphQLType(type.ofType))
    case let type as GraphQLNonNull:
        return .nonNull(graphqlTypeToSwiftUIGraphQLNonNullType(type.ofType))
    default:
        fatalError("Can't convert this type")
    }
}

private func graphqlTypeToSwiftUIGraphQLNonNullType(_ type: GraphQLNullableType) -> SwiftUIGraphQL.NonNullType {
    switch type {
    case let type as GraphQLNamedType:
        if let scalar = type as? GraphQLScalarType {
            return .named(genTypeName(forScalar: scalar))
        } else {
            return .named(type.name)
        }
    default:
        return .nonNull(graphqlTypeToSwiftUIGraphQLType(type))
    }
}
    
private func genTypeName(forScalar type: GraphQLScalarType) -> String {
    switch type.name {
    case "Boolean":
        return "Bool"
    case "Int", "Float", "String", "ID":
        return type.name
    default:
        if let specifiedByURL = type.specifiedByURL,
           let foundationScalar = foundationScalars[specifiedByURL] {
            return foundationScalar
        } else {
            fatalError("Don't know how to generate code for this Scalar!")
        }
    }
}

/// Predefined types in Foundation that we should use for Scalars specified by the following URLs
private let foundationScalars = [
    "https://tools.ietf.org/html/rfc1738": "URL",
    "https://tools.ietf.org/html/rfc3339": "Date"
]
