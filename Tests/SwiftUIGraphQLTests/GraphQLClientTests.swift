import XCTest
import GraphQL
@testable import SwiftUIGraphQL

final class GraphQLClientTests: XCTestCase {
    struct MyQuery: QueryOperation, Equatable {
        let foo: Int
        static let query = "{ foo }"
        static let selection = selectionFromQuery(schema: schema, query)
        static let schema = try! GraphQLSchema(query: GraphQLObjectType(name: "Query", fields: [
            "foo": GraphQLField(type: GraphQLInt)
        ]))
    }

    func testWatchCacheFirstElseNetworkPolicy() async throws {
        let networkObj: SwiftUIGraphQL.Value.Object = ["foo": 1]
        let client = MockGraphQLClient(response: .data(.object(networkObj)))

        let cachedObj: SwiftUIGraphQL.Value.Object = ["foo": 0]
        await client.cache.mergeQuery(cachedObj, selection: MyQuery.selection.assumingNoVariables, updater: nil)

        var iterator = await client.watch(MyQuery.self, cachePolicy: .cacheFirstElseNetwork).makeAsyncIterator()
        let firstValue = try await iterator.next()!
        XCTAssertEqual(firstValue, MyQuery(foo: 0))
        
        await client.cache.mergeQuery(["foo": 2], selection: MyQuery.selection.assumingNoVariables, updater: nil)
        let secondValue = try await iterator.next()!
        XCTAssertEqual(secondValue, MyQuery(foo: 2))
    }

    func testWatchCacheFirstThenNetworkPolicy() async throws {
        let networkObj: SwiftUIGraphQL.Value.Object = ["foo": 1]
        let client = MockGraphQLClient(response: .data(.object(networkObj)))

        let cachedObj: SwiftUIGraphQL.Value.Object = ["foo": 0]
        await client.cache.mergeQuery(cachedObj, selection: MyQuery.selection.assumingNoVariables, updater: nil)

        var iterator = await client.watch(MyQuery.self, cachePolicy: .cacheFirstThenNetwork).makeAsyncIterator()
        let firstValue = try await iterator.next()!
        XCTAssertEqual(firstValue, MyQuery(foo: 0))

        await client.cache.mergeQuery(["foo": 2], selection: MyQuery.selection.assumingNoVariables, updater: nil)
        let secondValue = try await iterator.next()!
        XCTAssertEqual(secondValue, MyQuery(foo: 1))
    }

    func testWatchCacheNetworkOnlyPolicy() async throws {
        let networkObj: SwiftUIGraphQL.Value.Object = ["foo": 1]
        let client = MockGraphQLClient(response: .data(.object(networkObj)))

        let cachedObj: SwiftUIGraphQL.Value.Object = ["foo": 0]
        await client.cache.mergeQuery(cachedObj, selection: MyQuery.selection.assumingNoVariables, updater: nil)

        var iterator = await client.watch(MyQuery.self, cachePolicy: .networkOnly).makeAsyncIterator()
        let firstValue = try await iterator.next()!
        XCTAssertEqual(firstValue, MyQuery(foo: 1))
    }
}
