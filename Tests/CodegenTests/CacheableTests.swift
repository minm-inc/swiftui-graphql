import XCTest
@testable import GraphQL
import Codegen

class CacheableTests: XCTestCase {
    func testAttachCachableFieldsOnInterface() {
        let document = try! parse(source: """
            {
                a {
                    ... on B {
                        x
                    }
                }
            }
        """)
        let iface = try! GraphQLInterfaceType(
            name: "Iface",
            fields: ["id": GraphQLField(type: GraphQLID)]
        )
        let schema = try! GraphQLSchema(
            query: GraphQLObjectType(
                name: "Query",
                fields: [
                    "a": GraphQLField(type: iface)
                ]
            ),
            types: [
                GraphQLInterfaceType(
                    name: "B",
                    interfaces: [iface],
                    fields: ["id": GraphQLField(type: GraphQLID)]
                )
            ]
        )
        let actual = attachCacheableFields(schema: schema, document: document)

        let expected = try! parse(source: """
            {
                a {
                    ... on B {
                        x
                        id
                        __typename
                    }
                    id
                    __typename
                }
            }
        """)
        XCTAssertEqual(actual, expected)
    }
}
