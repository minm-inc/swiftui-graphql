import XCTest
@testable import SwiftUIGraphQL
import GraphQL

final class CacheTests: XCTestCase {
    func testMergeCacheObjectsInList() async {
        let incoming: [ObjectKey: SwiftUIGraphQL.Value] = [
            "foo": .object([
                "__typename": .string("Foo"),
                "id": .string("1"),
                "bars": .list([
                    .object([
                        "__typename": .string("Bar"),
                        "id": .string("1")
                    ])
                ])
            ])
        ]
        let selection = ResolvedSelection<Never>(
            fields: [
                "foo": .init(name: "foo", arguments: [:], type: .named("Foo"), nested: .init(
                    fields: [
                        "__typename": .init(name: "__typename", arguments: [:], type: .named("String")),
                        "id": .init(name: "id", arguments: [:], type: .named("String")),
                        "bars": .init(name: "bars", arguments: [:], type: .list(.named("Bar")), nested: .init(
                            fields: [
                                "__typename": .init(name: "__typename", arguments: [:], type: .named("String")),
                                "id": .init(name: "id", arguments: [:], type: .named("String"))
                            ],
                            conditional: [:]
                        ))
                    ],
                    conditional: [:]
                ))
            ],
            conditional: [:]
        )
        let existingCache: [CacheKey: CacheObject] = [
            .object(typename: "Foo", id: "1"): [:]
        ]
        let expectedCache: [CacheKey: CacheObject] = [
            .object(typename: "Foo", id: "1"): [
                "__typename": .string("Foo"),
                "id": .string("1"),
                "bars": .list([
                    .reference(.object(typename: "Bar", id: "1"))
                ])
            ],
            .object(typename: "Bar", id: "1"): [
                "__typename": .string("Bar"),
                "id": .string("1")
            ],
            .queryRoot: [
                "foo": .reference(.object(typename: "Foo", id: "1"))
            ]
        ]
        let cache = Cache(store: existingCache)

        await cache.mergeQuery(incoming,
                               selection: selection,
                               updater: nil)

        let store = await cache.store.store
        XCTAssertEqual(store, expectedCache)
    }
    
    func testCacheFieldsWithDifferentArguments() async {
        let incoming: [ObjectKey: SwiftUIGraphQL.Value] = [
            "foo": .object([
                "__typename": .string("Foo"),
                "id": .string("1"),
                "bar": .int(42)
            ])
        ]
        let selection = ResolvedSelection<Never>(
            fields: [
                "foo": .init(name: "foo", arguments: [:], type: .named(""), nested: .init(
                    fields: [
                        "__typename": .init(name: "__typename", arguments: [:], type: .named(""), nested: nil),
                        "id": .init(name: "id", arguments: [:], type: .named(""), nested: nil),
                        "bar": .init(name: "bar", arguments: ["a": .boolean(false)], type: .named(""), nested: nil),
                    ],
                    conditional: [:]
                ))
            ],
            conditional: [:]
        )
        let existingCache: [CacheKey: CacheObject] = [
            .object(typename: "Foo", id: "1"): [
                NameAndArgumentsKey(name: "bar", args: ["a": .boolean(true)]): .int(24)
            ]
        ]
        let cache = Cache(store: existingCache)
        let _ = await cache.mergeQuery(incoming, selection: selection, updater: nil)
        let cacheFoo = await cache.store[.object(typename: "Foo", id: "1")]!
        XCTAssertEqual(
            cacheFoo[NameAndArgumentsKey(name: "bar", args: ["a": .boolean(false)])],
            .int(42)
        )
        XCTAssertEqual(
            cacheFoo[NameAndArgumentsKey(name: "bar", args: ["a": .boolean(true)])],
            .int(24)
        )
    }

    func testCacheFieldsWithSameArguments() async {
        let incoming: [ObjectKey: SwiftUIGraphQL.Value] = [
            "foo": .object([
                "__typename": .string("Foo"),
                "id": .string("1"),
                "bar": .int(42)
            ])
        ]
        let selection = ResolvedSelection<Never>(
            fields: [
                "foo": .init(name: "foo", arguments: [:], type: .named(""), nested: .init(
                    fields: [
                        "__typename": .init(name: "__typename", arguments: [:], type: .named(""), nested: nil),
                        "id": .init(name: "id", arguments: [:], type: .named(""), nested: nil),
                        "bar": .init(name: "bar", arguments: ["a": .boolean(true)], type: .named(""), nested: nil),
                    ],
                    conditional: [:]
                ))
            ],
            conditional: [:]
        )
        let existingCache: [CacheKey: CacheObject] = [
            .object(typename: "Foo", id: "1"): [
                NameAndArgumentsKey(name: "bar", args: ["a": .boolean(true)]): .int(24)
            ]
        ]
        let cache = Cache(store: existingCache)
        let _ = await cache.mergeQuery(incoming, selection: selection, updater: nil)
        let cacheFoo = await cache.store[.object(typename: "Foo", id: "1")]!
        XCTAssertEqual(
            cacheFoo[NameAndArgumentsKey(name: "bar", args: ["a": .boolean(true)])],
            .int(42)
        )
    }

    /// Tests that a nested field that becomes a different type eventually gets updated
    func testUpdateQuerySwitchingTypes() async throws {
        let interfaceType = try GraphQLInterfaceType(name: "Interface", fields: [
            "id": GraphQLField(type: GraphQLString)
        ])
        let schema = try GraphQLSchema(query: GraphQLObjectType(name: "Query", fields: [
            "x": GraphQLField(type: interfaceType)
        ]), types: [
            GraphQLObjectType(name: "Foo", fields: [
                "id": GraphQLField(type: GraphQLString),
                "foo": GraphQLField(type: GraphQLInt)
            ], interfaces: [interfaceType]),
            GraphQLObjectType(name: "Bar", fields: [
                "id": GraphQLField(type: GraphQLString),
                "bar": GraphQLField(type: GraphQLInt)
            ], interfaces: [interfaceType])
        ])
        let selection = selectionFromQuery(schema: schema, """
        {
            x {
                __typename
                id
                ... on Foo {
                    foo
                }
                ... on Bar {
                    bar
                }
            }
        }
        """).assumingNoVariables
        let cache = Cache(store: [
            .queryRoot: [
                "x": .reference(.object(typename: "Foo", id: "1"))
            ],
            .object(typename: "Foo", id: "1"): [
                "id": .string("1"),
                "foo": .int(42)
            ]
        ])
        let incoming: SwiftUIGraphQL.Value.Object = [
            "x": [
                "__typename": "Bar",
                "id": "1",
                "bar": "hello world"
            ]
        ]
        await cache.mergeQuery(incoming, selection: selection, updater: nil)
        let actual = await cache.objectFromSelection(selection)
        XCTAssertEqual(actual, incoming)
    }

    func testCacheUpdaterMarksKeysAsChanged() async {
        let key = CacheKey.object(typename: "Foo", id: "1")
        let cache = Cache(store: [
            key: [
                "__typename": .string("Foo"),
                "id": .string("1"),
                "x": .int(42)
            ],
            .queryRoot: [
                "foo1": .reference(key)
            ]
        ])
        let fooType = try! GraphQLObjectType(name: "Foo", fields: [
            "id": GraphQLField(type: GraphQLString),
            "x": GraphQLField(type: GraphQLInt)
        ])
        let schema = try! GraphQLSchema(query: GraphQLObjectType(name: "Query", fields: [
            "foo1": GraphQLField(type: fooType),
            "foo2": GraphQLField(type: fooType)
        ]))
        let updater: Cache.Updater = { cacheObject, cache in
            await cache.update(key, with: .update({ x in
                guard case var .object(obj) = x else { fatalError() }
                obj["x"] = .int(43)
                return .object(obj)
            }))
        }

        var iterator = await cache.listenToChanges(selection: selectionFromQuery(schema: schema, "{ foo1 { x } }").assumingNoVariables,
                                                   on: .queryRoot).makeAsyncIterator()

        await cache.mergeQuery(["foo2": ["x": 42]],
                               selection: selectionFromQuery(schema: schema, "{ foo2 { x } }").assumingNoVariables,
                               updater: updater)

        let nextValue = await iterator.next()!
        let expected: [ObjectKey: SwiftUIGraphQL.Value] = ["foo1": ["x": 43]]
        XCTAssertEqual(nextValue, expected)
    }

    func testQueryRootGetsUpdated() async {
        let cache = Cache()

        var selection = ResolvedSelection<Never>(
            fields: ["foo": .init(name: "foo", arguments: [:], type: .named("Int"))],
            conditional: [:]
        )
        await cache.mergeQuery(["foo": .int(42)], selection: selection, updater: nil)

        var actual = await cache.store[.queryRoot]!
        var expected: CacheObject = [
            "foo": .int(42)
        ]

        XCTAssertEqual(expected, actual)


        selection = ResolvedSelection<Never>(
            fields: ["bar": .init(name: "bar", arguments: [:], type: .named("Int"))],
            conditional: [:]
        )
        await cache.mergeQuery(["bar": .int(88)], selection: selection, updater: nil)

        actual = await cache.store[.queryRoot]!
        expected = [
            "foo": .int(42),
            "bar": .int(88)
        ]

        XCTAssertEqual(expected, actual)
    }

    func testExtractSelectionFromRootCache() async {
        let cache = Cache(store: [
            .queryRoot: [
                "foo": .object([
                    "bar": .object([
                        "baz": .int(42)
                    ]),
                    "qux": .string("hello")
                ])
            ]
        ])
        let schema = try! GraphQLSchema(query: GraphQLObjectType(
            name: "Query",
            fields: [
                "foo": GraphQLField(type: GraphQLObjectType(name: "Foo", fields: [
                    "bar": GraphQLField(type: GraphQLObjectType(name: "Bar", fields: [
                        "baz": GraphQLField(type: GraphQLInt)
                    ])),
                    "qux": GraphQLField(type: GraphQLString)
                ]))
            ]
        ))
        var selection = selectionFromQuery(schema: schema, """
        {
           foo { bar { baz } }
        }
        """).assumingNoVariables
        var actual = await cache.objectFromSelection(selection)
        var expected: [ObjectKey: SwiftUIGraphQL.Value] = [
            "foo": .object([
                "bar": .object([
                    "baz": .int(42)
                ])
            ])
        ]
        XCTAssertEqual(expected, actual)

        selection = selectionFromQuery(schema: schema, """
        {
           foo { qux }
        }
        """).assumingNoVariables
        actual = await cache.objectFromSelection(selection)
        expected = [
            "foo": .object([
                "qux": .string("hello")
            ])
        ]
        XCTAssertEqual(expected, actual)
    }

    func testExtractSelectionFromRootCacheWithVariables() async {
        let cache = Cache(store: [
            .queryRoot: [
                NameAndArgumentsKey(name: "foo", args: ["x": .int(0)]): .int(42),
                NameAndArgumentsKey(name: "foo", args: ["x": .int(1)]): .int(43),
            ]
        ])
        let schema = try! GraphQLSchema(query: GraphQLObjectType(
            name: "Query",
            fields: [
                "foo": GraphQLField(type: GraphQLInt, args: ["x": GraphQLArgument(type: GraphQLInt)])
            ]
        ))
        var selection = selectionFromQuery(schema: schema, "{ foo(x: 0) }").assumingNoVariables
        var actual = await cache.objectFromSelection(selection)
        XCTAssertEqual(["foo": .int(42)], actual)

        selection = selectionFromQuery(schema: schema, "{ foo(x: 1) }").assumingNoVariables
        actual = await cache.objectFromSelection(selection)
        XCTAssertEqual(["foo": .int(43)], actual)
    }


    func testValueFromCacheWithReferences() async {
        let cache = Cache(store: [
            .object(typename: "Foo", id: "1"): [
                "bar": .int(42)
            ],
            .queryRoot: [
                "foo": .reference(.object(typename: "Foo", id: "1"))
            ]
        ])
        let schema = try! GraphQLSchema(query: GraphQLObjectType(
            name: "Query",
            fields: [
                "foo": GraphQLField(type: GraphQLObjectType(name: "Foo", fields: [
                    "id": GraphQLField(type: GraphQLString),
                    "bar": GraphQLField(type: GraphQLInt)
                ]))
            ]
        ))
        let selection = selectionFromQuery(schema: schema, "{ foo { bar } }").assumingNoVariables
        let actual = await cache.objectFromSelection(selection)
        let expected: [ObjectKey: SwiftUIGraphQL.Value] = [
            "foo": .object([
                "bar": .int(42)
            ])
        ]
        XCTAssertEqual(expected, actual)
    }

    func testListenToChanges() async {
        let cache = Cache(store: [
            .object(typename: "Foo", id: "1"): [
                "bar": .int(42)
            ],
            .queryRoot: [
                "foo": .reference(.object(typename: "Foo", id: "1"))
            ]
        ])
        let schema = try! GraphQLSchema(query: GraphQLObjectType(
            name: "Query",
            fields: [
                "foo": GraphQLField(type: GraphQLObjectType(name: "Foo", fields: [
                    "id": GraphQLField(type: GraphQLString),
                    "bar": GraphQLField(type: GraphQLInt)
                ]))
            ]
        ))
        let selection = selectionFromQuery(schema: schema, "{ foo { bar } }").assumingNoVariables
        var iterator = await cache.listenToChanges(selection: selection, on: .queryRoot).makeAsyncIterator()
        let incoming: SwiftUIGraphQL.Value.Object = [
            "foo": [
                "__typename": "Foo",
                "id": "1",
                "bar": 43
            ]
        ]
        await cache.mergeQuery(incoming, selection: selection, updater: nil)
        let newValue = await iterator.next()!
        XCTAssertEqual(["foo": ["bar": 43]], newValue)

        let newObject: SwiftUIGraphQL.Value.Object = [
            "foo": [
                "__typename": "Foo",
                "id": "2",
                "bar": 10
            ]
        ]
        await cache.mergeQuery(newObject, selection: selection, updater: nil)
        let newValueWithChangedObject = await iterator.next()!
        XCTAssertEqual(["foo": ["bar": 10]], newValueWithChangedObject)
    }

    func testListenToChangesIgnoresIrrelevantChanges() async {
        let cache = Cache(store: [.queryRoot: ["foo": .int(1)]])
        let schema = try! GraphQLSchema(query: GraphQLObjectType(
            name: "Query",
            fields: [
                "foo": GraphQLField(type: GraphQLInt),
                "bar": GraphQLField(type: GraphQLInt)
            ]
        ))
        let selection = selectionFromQuery(schema: schema, "{ foo }").assumingNoVariables
        var iterator = await cache.listenToChanges(selection: selection, on: .queryRoot).makeAsyncIterator()
        await cache.mergeQuery(["bar": 2],
                               selection: selectionFromQuery(schema: schema, "{ bar }").assumingNoVariables,
                               updater: nil)
        await cache.mergeQuery(["foo": 3],
                               selection: selectionFromQuery(schema: schema, "{ foo }").assumingNoVariables,
                               updater: nil)
        let actual = await iterator.next()!
        XCTAssertEqual(["foo": 3], actual)
    }

    func testDoesntSendCacheUpdatesForIdenticalUpdate() async {
        let cache = Cache(store: [.queryRoot: ["foo": .int(1)]])
        let schema = try! GraphQLSchema(query: GraphQLObjectType(
            name: "Query",
            fields: ["foo": GraphQLField(type: GraphQLInt)]
        ))
        let selection = selectionFromQuery(schema: schema, "{ foo }").assumingNoVariables
        let iterator = await cache.listenToChanges(selection: selection, on: .queryRoot).makeAsyncIterator()
        await cache.mergeQuery(["foo": 1],
                               selection: selectionFromQuery(schema: schema, "{ foo }").assumingNoVariables,
                               updater: nil)

        let expectation = expectation(description: "Doesn't get foo = 1")
        // Need to await for iterator concurrently as it has buffer size of 1
        Task {
            var iterator = iterator
            let actual = await iterator.next()!
            XCTAssertEqual(["foo": 2], actual)
            expectation.fulfill()
        }
        await cache.mergeQuery(["foo": 2],
                               selection: selectionFromQuery(schema: schema, "{ foo }").assumingNoVariables,
                               updater: nil)
        await waitForExpectations(timeout: 5)
    }

    func testClearingCacheSendsChange() async {
        let cache = Cache(store: [.queryRoot: ["x": .int(42)]])
        let schema = try! GraphQLSchema(query: GraphQLObjectType(name: "Query", fields: [
            "x": GraphQLField(type: GraphQLInt)
        ]))
        let selection =  selectionFromQuery(schema: schema, "{x}").assumingNoVariables
        var iterator = await cache.listenToChanges(selection: selection, on: .queryRoot)
                                  .makeAsyncIterator()
        await cache.clear()
        let change = await iterator.next()!
        XCTAssertNil(change)
    }

    func testConditionalSelectionsArePickedUpAsChanged() async {
        let cacheKey = CacheKey.object(typename: "Foo", id: "1")
        var store = Cache.Store(initialStore: [
            .queryRoot: [
                "x": .reference(cacheKey)
            ],
            cacheKey: [
                "__typename": .string("Foo"),
                "id": .string("1"),
                "y": .int(42)
            ]
        ])
        let incoming: CacheObject = [
            "__typename": .string("Foo"),
            "id": .string("1"),
            "y": .int(43)
        ]
        store.mergeCacheObject(incoming, into: cacheKey)
        let ifaceType = try! GraphQLInterfaceType(name: "Iface", fields: [
            "id": GraphQLField(type: GraphQLString)
        ])
        let schema = try! GraphQLSchema(query: GraphQLObjectType(name: "Query", fields: [
            "x": GraphQLField(type: ifaceType)
        ]), types: [GraphQLObjectType(name: "Foo", fields: [
            "id": GraphQLField(type: GraphQLString),
            "y": GraphQLField(type: GraphQLInt),
        ], interfaces: [ifaceType])])

        let selection = selectionFromQuery(schema: schema, "{ x { ... on Foo { y } } }").assumingNoVariables
        XCTAssertTrue(store.selectionChanged(selection, on: .queryRoot))
    }

    func testClearingCacheWithListenerSendsNil() async {
        let key = CacheKey.object(typename: "Foo", id: "1")
        let cache = Cache(store: [
            key: [
                "x": .int(42)
            ]
        ])

        let fooType = try! GraphQLObjectType(name: "Foo", fields: [
            "x": GraphQLField(type: GraphQLInt)
        ])

        let schema = try! GraphQLSchema(query: GraphQLObjectType(name: "Query", fields: [
            "foo": GraphQLField(type: fooType)
        ]))
        let selection = selection("{x}", on: fooType, schema: schema).assumingNoVariables

        var iterator = await cache.listenToChanges(selection: selection, on: key).makeAsyncIterator()
        await cache.clear()
        let next = await iterator.next()!
        XCTAssertNil(next)
    }

//
//    func testUpdateQueryWithNewResponse() {
//        /**
//         Imagine 2 queries like:
//         ```graphql
//         query a {
//            foo {
//                __typename id
//                baz { qux }
//            }
//         }
//         query b {
//            foo {
//                __typename id
//                baz { qan }
//            }
//         }
//         ```
//
//         where `baz` is a list of objects *without any ID*.
//         Query A is executed and the cache is stored as:
//         ```
//            foo:1 => {
//                baz => [{ qux => 42 }]
//            }
//         ```
//         And now query B is executed, updating the cache to:
//         ```
//            foo:1 => {
//                baz => [{ qan => 42 }]
//            }
//         ```
//         So we go to update query A's response with the new data in the cache, but `qux` isn't present on `baz`!
//
//         What do we do here? We should handle this.
//         */
//
//    }
}

extension AsyncSequence {
    func first() async throws -> Element? {
        var iterator = makeAsyncIterator()
        return try await iterator.next()
    }
}


fileprivate extension Cache {
    func objectFromSelection(_ selection: ResolvedSelection<Never>) -> SwiftUIGraphQL.Value.Object? {
        value(from: store[.queryRoot]!, selection: selection)
    }
}
