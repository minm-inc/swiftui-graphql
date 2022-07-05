import XCTest
@testable import SwiftUIGraphQL

final class CacheTests: XCTestCase {
    func testMergeCacheObjectsInList() async {
        let incoming: [ObjectKey: Value] = [
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
        let existingCache: Cache.Store = [
            CacheKey(type: "Foo", id: "1"): [:]
        ]
        let expectedCache: Cache.Store = [
            CacheKey(type: "Foo", id: "1"): [
                "__typename": .string("Foo"),
                "id": .string("1"),
                "bars": .list([
                    .reference(CacheKey(type: "Bar", id: "1"))
                ])
            ],
            CacheKey(type: "Bar", id: "1"): [
                "__typename": .string("Bar"),
                "id": .string("1")
            ]
        ]
        let cache = Cache(store: existingCache)

        let expectation = XCTestExpectation()
        Task {
            let changedKeys = try await cache.publisher.first().values.first()!.0
            XCTAssertEqual(changedKeys, [
                CacheKey(type: "Foo", id: "1"),
                CacheKey(type: "Bar", id: "1")
            ])
            expectation.fulfill()
        }

        await cache.mergeCache(incoming: incoming,
                               selection: selection,
                               updater: nil)

        let store = await cache.store
        XCTAssertEqual(store, expectedCache)
    }
    
    func testCacheFieldsWithDifferentArguments() async {
        let incoming: [ObjectKey: Value] = [
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
        let existingCache: Cache.Store = [
            CacheKey(type: "Foo", id: "1"): [
                NameAndArgumentsKey(name: "bar", args: ["a": .boolean(true)]): .int(24)
            ]
        ]
        let cache = Cache(store: existingCache)
        let _ = await cache.mergeCache(incoming: incoming, selection: selection, updater: nil)
        let cacheFoo = await cache.store[CacheKey(type: "Foo", id: "1")]!
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
        let incoming: [ObjectKey: Value] = [
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
        let existingCache: Cache.Store = [
            CacheKey(type: "Foo", id: "1"): [
                NameAndArgumentsKey(name: "bar", args: ["a": .boolean(true)]): .int(24)
            ]
        ]
        let cache = Cache(store: existingCache)
        let _ = await cache.mergeCache(incoming: incoming, selection: selection, updater: nil)
        let cacheFoo = await cache.store[CacheKey(type: "Foo", id: "1")]!
        XCTAssertEqual(
            cacheFoo[NameAndArgumentsKey(name: "bar", args: ["a": .boolean(true)])],
            .int(42)
        )
    }

    func testUpdateQuerySwitchingTypes() {
        let existing = Value.object([
            "__typename": .string("Root"),
            "id": .string("1"),
            "x": .object([
                "__typename": .string("Foo"),
                "id": .string("1"),
                "foo": .int(42)
            ])
        ])
        let selection = ResolvedSelection<Never>(
            fields: [
                "__typename": .init(name: "__typename", arguments: [:], type: .named("String")),
                "id": .init(name: "id", arguments: [:], type: .named("String")),
                "x": .init(name: "x", arguments: [:], type: .named("Root"), nested: .init(
                    fields: [
                        "__typename": .init(name: "__typename", arguments: [:], type: .named("String")),
                        "id": .init(name: "id", arguments: [:], type: .named("String"))
                    ],
                    conditional: [
                        "Foo": [
                            "foo": .init(name: "foo", arguments: [:], type: .named("Int"))
                        ],
                        "Bar": [
                            "bar": .init(name: "bar", arguments: [:], type: .named("String"))
                        ]
                    ]
                ))
            ],
            conditional: [:]
        )
        let cache: Cache.Store = [
            CacheKey(type: "Root", id: "1"): [
                "__typename": .string("Root"),
                "id": .string("1"),
                "x": .reference(CacheKey(type: "Bar", id: "1"))
            ],
            CacheKey(type: "Bar", id: "1"): [
                "__typename": .string("Bar"),
                "id": .string("1"),
                "bar": .string("hello world")
            ]
        ]
        let actual = update(
            value: existing,
            selection: selection,
            changedKeys: [CacheKey(type: "Root", id: "1")],
            cacheStore: cache
        )
        let expected = Value.object([
            "__typename": .string("Root"),
            "id": .string("1"),
            "x": .object([
                "__typename": .string("Bar"),
                "id": .string("1"),
                "bar": .string("hello world")
            ])
        ])
        XCTAssertEqual(actual, expected)
    }

    func testCacheUpdaterMarksKeysAsChanged() async {
        let key = CacheKey(type: "Foo", id: "1")
        let cache = Cache(store: [
            key: [
                "__typename": .string("Foo"),
                "id": .string("1"),
                "x": .int(42)
            ]
        ])
        let selection = ResolvedSelection<Never>(
            fields: ["foo": .init(name: "foo", arguments: [:], type: .named("Int"))],
            conditional: [:]
        )
        let updater: Cache.Updater = { cacheObject, cache in
            await cache.update(key, with: .update({ x in
                guard case var .object(obj) = x else { fatalError() }
                obj["x"] = .int(43)
                return .object(obj)
            }))
        }

        let expectation = XCTestExpectation()
        Task {
            let changedKeys = try await cache.publisher.first().values.first()!.0
            XCTAssertEqual(changedKeys, [key])
            expectation.fulfill()
        }

        await cache.mergeCache(incoming: ["foo": .int(42)], selection: selection, updater: updater)
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
