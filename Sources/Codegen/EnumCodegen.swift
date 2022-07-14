import GraphQL
import SwiftSyntax

public func genEnums(schema: GraphQLSchema) -> [DeclSyntax] {
    let swiftGen = SwiftGen()
    return schema.typeMap.values
        .filter { !$0.name.hasPrefix("__") }
        .sorted(by: { $0.name > $1.name })
        .compactMap { type in
            guard let enumType = type as? GraphQLEnumType else { return nil }
            return Decl.enum(name: enumType.name.firstUppercased,
                             cases: enumType.values.map {
                Decl.Case(name: $0.name.lowercased(), rawValue: .stringLiteral($0.name))
            },
                             decls: [
                                .let(name: "id",
                                     type: .named("Self"),
                                     accessor: .get(.expr(.`self`)),
                                     access: .public)
                             ],
                             conforms: ["String", "Hashable", "Codable", "CaseIterable", "Identifiable", "Sendable"],
                             genericParameters: [])
        }.map(swiftGen.gen(decl:))
}
