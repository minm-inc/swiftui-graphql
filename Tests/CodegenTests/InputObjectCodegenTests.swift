import XCTest
import GraphQL
@testable import Codegen

final class InputObjectCodegenTests: XCTestCase {
    func testInputObjectCodegen() throws {
        let inputObjectType = try GraphQLInputObjectType(
            name: "Location",
            fields: [
                "city": InputObjectField(type: GraphQLNonNull(GraphQLString)),
                "countryCode": InputObjectField(type: GraphQLNonNull(GraphQLString))
            ]
        )
        let enumSyntax = genInputObjectType(inputObjectType)
        var output = ""
        SwiftGen().gen(decl: enumSyntax).write(to: &output)
        XCTAssertEqual(output, """
public struct Location: Hashable, Codable, Sendable {
    public let city: String
    public let countryCode: String
}

""")
    }
}
