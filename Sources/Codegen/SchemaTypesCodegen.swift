import GraphQL
import SwiftSyntax

public func genSchemaTypes(schema: GraphQLSchema) -> [DeclSyntax] {
    let swiftGen = SwiftGen()
    return schema.typeMap.values
        .filter { !$0.name.hasPrefix("__") }
        .sorted(by: { $0.name > $1.name })
        .compactMap { type in
            switch type {
            case let type as GraphQLEnumType:
                return genEnumType(type)
            case let type as GraphQLInputObjectType:
                return genInputObjectType(type)
            default:
                return nil
            }
        }.map(swiftGen.gen(decl:))
}

func genEnumType(_ enumType: GraphQLEnumType) -> Decl {
    let cases = enumType.values.map {
        Decl.Case(name: $0.name.lowercased(), rawValue: .stringLiteral($0.name))
    }
    return Decl.enum(name: enumType.name.firstUppercased,
                     cases: cases,
                     decls: [
                        .let(name: "id",
                             type: .named("Self"),
                             accessor: .get(.expr(.`self`)),
                             access: .public)
                     ],
                     conforms: ["String", "Hashable", "Codable", "CaseIterable", "Identifiable", "Sendable"],
                     genericParameters: [])
}

func genInputObjectType(_ inputObjectType: GraphQLInputObjectType) -> Decl {
    let decls = inputObjectType.fields.map { name, field in
        Decl.let(name: name, type: genType(for: field.type), access: .public)
    }
    return Decl.struct(name: inputObjectType.name,
                       decls: decls,
                       conforms: ["Hashable", "Codable", "Sendable"])
}
