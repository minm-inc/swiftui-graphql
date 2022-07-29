import XCTest
import GraphQL
@testable import SwiftUIGraphQL

final class MockGraphQLClientTests: XCTestCase {
    struct FooQuery: QueryOperation, Equatable {
        let foo: Int
        static let query = "{ foo }"
        static let selection = selectionFromQuery(schema: schema, query)
        static let schema = try! GraphQLSchema(query: GraphQLObjectType(name: "Query", fields: [
            "foo": GraphQLField(type: GraphQLInt)
        ]))
    }
    struct BarQuery: QueryOperation, Equatable {
        let bar: Int
        static let query = "{ foo }"
        static let selection = selectionFromQuery(schema: schema, query)
        static let schema = try! GraphQLSchema(query: GraphQLObjectType(name: "Query", fields: [
            "foo": GraphQLField(type: GraphQLInt)
        ]))
    }

    func testMockedResponses() async throws {
        let client = MockGraphQLClient {
            MockResponse(FooQuery.self, responseURL: Bundle.module.url(forResource: "fooResponse", withExtension: "json")!)
            MockResponse(BarQuery.self, response: .data(["bar": 10]))
        }
        let fooRes = try await client.execute(FooQuery.self)
        XCTAssertEqual(FooQuery(foo: 42), fooRes)
        let barRes = try await client.execute(BarQuery.self)
        XCTAssertEqual(BarQuery(bar: 10), barRes)
    }
}
