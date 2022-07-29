import XCTest
import GraphQL
@testable import Codegen

final class EnumCodegenTests: XCTestCase {
    func testEnumCodegen() throws {
        let enumType = try GraphQLEnumType(name: "Animal", values: [
            "CAT": GraphQLEnumValue(value: .string("CAT")),
            "DOG": GraphQLEnumValue(value: .string("DOG"))
        ])
        let enumSyntax = genEnumType(enumType)
        var output = ""
        SwiftGen().gen(decl: enumSyntax).write(to: &output)
        XCTAssertEqual(output, """
public enum Animal: String, Hashable, Codable, CaseIterable, Identifiable, Sendable {
    case cat = "CAT"
    case dog = "DOG"
    public var id: Self {
        self
    }
}

""")
    }
}
