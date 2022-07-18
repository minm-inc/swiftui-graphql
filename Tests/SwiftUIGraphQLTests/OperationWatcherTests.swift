import XCTest
@testable import SwiftUIGraphQL
import GraphQL

final class OperationWatcherTests: XCTestCase {
    @MainActor
    func testOperationWatcherReceivesCacheUpdates() async throws {
        struct FooQuery: QueryOperation {
            static let schema = try! GraphQLSchema(query: GraphQLObjectType(name: "Query", fields: [
                "foo": GraphQLField(type: GraphQLObjectType(name: "Foo", fields: [
                    "__typename": GraphQLField(type: GraphQLString),
                    "id": GraphQLField(type: GraphQLID),
                    "bar": GraphQLField(type: GraphQLInt)
                ]))
            ]))
            static let selection = selectionFromQuery(schema: schema, query)

            static var query: String = "{ foo { __typename id bar } }"

            let foo: Foo
            struct Foo: Decodable, Cacheable {
                static let selection = FooQuery.selection.fields["foo"]!.nested!
                let __typename: String
                let id: ID
                let bar: Int?
            }
        }
        let operation = OperationWatcher<FooQuery>()
        let client = MockGraphQLClient(response: .data([
            "foo": [
                "__typename": "Foo",
                "id": "1",
                "bar": 42
            ]
        ]))
        operation.client = client
        try await operation.execute(variables: NoVariables())
        await client.cache.update(.object(typename: "Foo", id: "1"), with: .update { old in
            guard case .object(var obj) = old else { fatalError() }
            obj["bar"] = .int(43)
            return .object(obj)
        })
        var iterator = operation.$result.first { $0.data?.foo.bar == 43 }.values.makeAsyncIterator()
        await client.cache.flushChanges()
        let result = await iterator.next()!
        XCTAssertEqual(43, result.data?.foo.bar)
    }

    @MainActor
    func testChangingVariablesDoesntSetDataToNil() async throws {
        struct FooQuery: QueryOperation {
            static let schema = try! GraphQLSchema(query: GraphQLObjectType(name: "Query", fields: [
                "foo": GraphQLField(type: GraphQLInt, args: ["x": GraphQLArgument(type: GraphQLInt)])
            ]))
            static let selection = selectionFromQuery(schema: schema, query)

            static var query: String = "query ($x: Int) { foo(x: 0) }"
            let foo: Int

            struct Variables: Equatable, Codable {
                let x: Int
            }
        }
        let watcher = OperationWatcher<FooQuery>()
        let client = MockGraphQLClient(response: .data(["foo": 1]))
        watcher.client = client
        let resultExpectation = expectation(description: "Receives two result changes")
        resultExpectation.expectedFulfillmentCount = 2
        var doneFirstQuery = false
        var results: [SwiftUIGraphQL.GraphQLResult<FooQuery>] = []

        let cancellable = watcher.$result.sink { result in
            if !doneFirstQuery { return }
            results.append(result)
            resultExpectation.fulfill()
        }

        try await watcher.execute(variables: FooQuery.Variables(x: 0))
        doneFirstQuery = true
        try await watcher.execute(variables: FooQuery.Variables(x: 1))
        waitForExpectations(timeout: 5)

        withExtendedLifetime(cancellable) {
            XCTAssertEqual(results[0].data?.foo, 1)
            XCTAssertTrue(results[0].isFetching)

            XCTAssertEqual(results[1].data?.foo, 1)
            XCTAssertFalse(results[1].isFetching)
        }
    }

    @MainActor
    func testClearingCacheRefetches() async throws {
        struct FooQuery: QueryOperation {
            static let schema = try! GraphQLSchema(query: GraphQLObjectType(name: "Query", fields: [
                "foo": GraphQLField(type: GraphQLInt)
            ]))
            static let selection = selectionFromQuery(schema: schema, query)

            static var query: String = "{ foo }"
            let foo: Int
        }

        let transportExpectation = expectation(description: "Makes two transport fetches")
        transportExpectation.expectedFulfillmentCount = 2

        struct MockTransport: Transport {
            let expectation: XCTestExpectation
            func makeRequest<T>(query: String, variables: [String : SwiftUIGraphQL.Value]?, response: T.Type) async throws -> GraphQLResponse<T> where T : Decodable {
                expectation.fulfill()
                return GraphQLResponse.data(Value.object(["foo": 0])) as! GraphQLResponse<T>
            }
        }

        let operation = OperationWatcher<FooQuery>()
        let client = GraphQLClient(transport: MockTransport(expectation: transportExpectation))
        operation.client = client
        try await operation()
        await client.cache.clear()
        waitForExpectations(timeout: 5)
    }

    @MainActor
    func testMutationDoesntAffectQueryRootCache() async throws {
        struct FooMutation: MutationOperation, Equatable {
            static let schema = try! GraphQLSchema(query: GraphQLObjectType(name: "Query", fields: ["foo": GraphQLField(type: GraphQLInt)]),
                                                   mutation: GraphQLObjectType(name: "Mutation",
                                                                               fields: ["foo": GraphQLField(type: GraphQLInt)]))
            static let selection = selectionFromQuery(schema: schema, query)

            static var query: String = "{ foo }"
            let foo: Int
        }
        let client = MockGraphQLClient(response: .data(["foo": 0]))
        let operation = OperationWatcher<FooMutation>()
        operation.client = client
        let res = try await operation.execute(variables: NoVariables())
        let queryRoot = await client.cache.store[.queryRoot]
        XCTAssertEqual(queryRoot, [:])
        XCTAssertEqual(res, FooMutation(foo: 0))
    }
}
