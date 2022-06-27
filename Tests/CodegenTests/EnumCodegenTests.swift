import XCTest
import GraphQL
import Codegen

final class EnumCodegenTests: XCTestCase {
    func testEnumCodegen() throws {
        let enumType = try GraphQLEnumType(name: "Animal", values: [
            "CAT": GraphQLEnumValue(value: .string("CAT")),
            "DOG": GraphQLEnumValue(value: .string("DOG"))
        ])
        let schema = try GraphQLSchema(query: GraphQLObjectType(name: "Query", fields: [
            "animal": GraphQLField(type: enumType)
        ]))
        
        let enumSyntax = genEnums(schema: schema).last!
        var output = ""
        enumSyntax.write(to: &output)
        XCTAssertEqual(output, """
public enum Animal: String, Hashable, Codable, CaseIterable, Identifiable {
    case cat = "CAT"
    case dog = "DOG"
    public var id: Self {
        self
    }
}

""")
    }
}
