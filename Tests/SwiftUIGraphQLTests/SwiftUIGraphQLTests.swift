import XCTest
@testable import SwiftUIGraphQL

final class SwiftUIGraphQLTests: XCTestCase {
    
    func testDecodingObjects() {
        struct Test1: Equatable, Decodable {
            struct Foo: Equatable, Decodable {
                let bar: String
            }
            let foo: Foo
        }
            
        let res = try! ValueDecoder().decode(Test1.self, from: .object([
            "foo": .object([
                "bar": .string("bar")
            ])
        ]))
        XCTAssertEqual(Test1(foo: Test1.Foo(bar: "bar")), res)
    }
    
    func testDecodingLists() {
        struct Test1: Equatable, Decodable {
            let strings: [String]
        }
            
        let res = try! ValueDecoder().decode(Test1.self, from: .object([
            "strings": .list([.string("hello"), .string("world")])
        ]))
        XCTAssertEqual(Test1(strings: ["hello", "world"]), res)
    }
    
    func testEncodingObjects() {
        struct Test1: Equatable, Encodable {
            struct Foo: Equatable, Encodable {
                let bar: String
            }
            let foo: Foo
        }
        
        let res: Value = try! ValueEncoder().encode(Test1(foo: Test1.Foo(bar: "hey")))
        
        XCTAssertEqual(.object(["foo": .object(["bar": .string("hey")])]), res)
    }
    
    func testEncodingLists() {
        struct Test1: Equatable, Encodable {
            let strings: [String]
        }
        
        let res: Value = try! ValueEncoder().encode(Test1(strings: ["hello", "world"]))
        
        XCTAssertEqual(.object(["strings": .list([.string("hello"), .string("world")])]), res)
    }
    
    func testMergeCacheObjectsInList() async {
        let incoming: UnCacheObject = [
            CacheField(name: "foo"): .object([
                CacheField(name: "__typename"): .string("Foo"),
                CacheField(name: "id"): .string("1"),
                CacheField(name: "bars"): .list([
                    .object([
                        CacheField(name: "__typename"): .string("Bar"),
                        CacheField(name: "id"): .string("1")
                    ])
                ])
            ])
        ]
        let existingCache: [CacheKey: CacheObject] = [
            CacheKey(type: "Foo", id: "1"): [:]
        ]
        let expectedCache: [CacheKey: CacheObject] = [
            CacheKey(type: "Foo", id: "1"): [
                CacheField(name: "__typename"): .string("Foo"),
                CacheField(name: "id"): .string("1"),
                CacheField(name: "bars"): .list([
                    .reference(CacheKey(type: "Bar", id: "1"))
                ])
            ],
            CacheKey(type: "Bar", id: "1"): [
                CacheField(name: "__typename"): .string("Bar"),
                CacheField(name: "id"): .string("1")
            ]
        ]
        let cache = Cache(store: existingCache)
        let changedObjs = await cache.mergeCache(incoming: incoming)
        let store = await cache.store
        XCTAssertEqual(store, expectedCache)
        XCTAssertEqual(Set(changedObjs.keys), [
            CacheKey(type: "Foo", id: "1"),
            CacheKey(type: "Bar", id: "1")
        ])
    }
    
    func testCacheFieldsWithDifferentArguments() async {
        let incoming = cacheObject(
            from: [
                "foo": .object([
                    "__typename": .string("Foo"),
                    "id": .string("1"),
                    "bars": .int(42)
                ])
            ],
            selections: [
                .field(.init(name: "foo", arguments: [:], type: .named(""), selections: [
                    .field(.init(name: "__typename", arguments: [:], type: .named(""), selections: [])),
                    .field(.init(name: "id", arguments: [:], type: .named(""), selections: [])),
                    .field(.init(name: "bars", arguments: ["a": .boolean(false)], type: .named(""), selections: []))
                ]))
            ]
        )
        let existingCache: [CacheKey: CacheObject] = [
            CacheKey(type: "Foo", id: "1"): [
                CacheField(name: "bars", args: ["a": .boolean(true)]): .int(24)
            ]
        ]
        let cache = Cache(store: existingCache)
        let _ = await cache.mergeCache(incoming: incoming)
        let cacheFoo = await cache.store[CacheKey(type: "Foo", id: "1")]!
        XCTAssertEqual(
            cacheFoo[CacheField(name: "bars", args: ["a": .boolean(false)])],
            .int(42)
        )
        XCTAssertEqual(
            cacheFoo[CacheField(name: "bars", args: ["a": .boolean(true)])],
            .int(24)
        )
    }
    
    func testCacheFieldsWithSameArguments() async {
        let incoming = cacheObject(
            from: [
                "foo": .object([
                    "__typename": .string("Foo"),
                    "id": .string("1"),
                    "bars": .int(42)
                ])
            ],
            selections: [
                .field(.init(name: "foo", arguments: [:], type: .named(""), selections: [
                    .field(.init(name: "__typename", arguments: [:], type: .named(""), selections: [])),
                    .field(.init(name: "id", arguments: [:], type: .named(""), selections: [])),
                    .field(.init(name: "bars", arguments: ["a": .boolean(true)], type: .named(""), selections: []))
                ]))
            ]
        )
        let existingCache: [CacheKey: CacheObject] = [
            CacheKey(type: "Foo", id: "1"): [
                CacheField(name: "bars", args: ["a": .boolean(true)]): .int(24)
            ]
        ]
        let cache = Cache(store: existingCache)
        let _ = await cache.mergeCache(incoming: incoming)
        let cacheFoo = await cache.store[CacheKey(type: "Foo", id: "1")]!
        XCTAssertEqual(
            cacheFoo[CacheField(name: "bars", args: ["a": .boolean(true)])],
            .int(42)
        )
    }
    
    func testUpdateQuerySwitchingTypes() {
        let existing = UnCacheValue.object([
            CacheField(name: "__typename"): .string("Root"),
            CacheField(name: "id"): .string("1"),
            CacheField(name: "x"): .object([
                CacheField(name: "__typename"): .string("Foo"),
                CacheField(name: "id"): .string("1"),
                CacheField(name: "foo"): .int(42)
            ])
        ])
        let cache: [CacheKey: CacheObject] = [
            CacheKey(type: "Root", id: "1"): [
                CacheField(name: "__typename"): .string("Root"),
                CacheField(name: "id"): .string("1"),
                CacheField(name: "x"): .reference(CacheKey(type: "Bar", id: "1"))
            ],
            CacheKey(type: "Bar", id: "1"): [
                CacheField(name: "__typename"): .string("Bar"),
                CacheField(name: "id"): .string("1"),
                CacheField(name: "bar"): .string("hello world")
            ]
        ]
        let actual = update(
            value: existing,
            selections: [
                .field(.init(name: "__typename", arguments: [:], type: .named("String"), selections: [])),
                .field(.init(name: "id", arguments: [:], type: .named("String"), selections: [])),
                .field(ResolvedSelection.Field(name: "x", arguments: [:], type: .named("Root"), selections: [
                    .field(.init(name: "__typename", arguments: [:], type: .named("String"), selections: [])),
                    .field(.init(name: "id", arguments: [:], type: .named("String"), selections: [])),
                    .fragment(typeCondition: "Foo", selections: [
                        .field(ResolvedSelection.Field(name: "foo", arguments: [:], type: .named("Int"), selections: []))
                    ]),
                    .fragment(typeCondition: "Bar", selections: [
                        .field(ResolvedSelection.Field(name: "bar", arguments: [:], type: .named("String"), selections: []))
                    ])
                ]))
            ],
            changedKeys: [CacheKey(type: "Root", id: "1")],
            cache: cache
        )
        let expected = UnCacheValue.object([
            CacheField(name: "__typename"): .string("Root"),
            CacheField(name: "id"): .string("1"),
            CacheField(name: "x"): .object([
                CacheField(name: "__typename"): .string("Bar"),
                CacheField(name: "id"): .string("1"),
                CacheField(name: "bar"): .string("hello world")
            ])
        ])
        XCTAssertEqual(actual, expected)
    }
    
    func testCacheObjectFromSelections() {
        let selection: ResolvedSelection<Never> = .field(
            .init(
                name: "addToLibrary",
                arguments: ["itemId": .string("album:13")],
                type: .named("AddToLibraryPayload"),
                selections: [
                    .field(.init(
                        name: "edge",
                        type: .nonNull(.named("LibraryItemEdge")),
                        selections: [
                            .field(.init(
                                name: "node",
                                type: .nonNull(.named("LibraryItem")),
                                selections: [
                                    .field(.init(
                                        name: "inLibrary",
                                        type: .named("Boolean")
                                    ))
                                ]
                            ))
                        ]
                    ))
                ]
            )
        )
        let obj: [String: Value]  = [
            "addToLibrary": .object([
                "edge": .object([
                    "node": .object([
                        "inLibrary": .boolean(true)
                    ])
                ])
            ])
        ]
        let cacheObj = cacheObject(from: obj, selections: [selection])
        let expected: UnCacheObject =  [
            CacheField(name: "addToLibrary", args: ["itemId": .string("album:13")]): .object([
                CacheField(name: "edge"): .object([
                    CacheField(name: "node"): .object([
                        CacheField(name: "inLibrary"): .boolean(true)
                    ])
                ])
            ])
        ]
        XCTAssertEqual(cacheObj, expected)
    }
    
    func testUpdateQueryWithNewResponse() {
        /**
         Imagine 2 queries like:
         ```graphql
         query a {
            foo {
                __typename id
                baz { qux }
            }
         }
         query b {
            foo {
                __typename id
                baz { qan }
            }
         }
         ```
         
         where `baz` is a list of objects *without any ID*.
         Query A is executed and the cache is stored as:
         ```
            foo:1 => {
                baz => [{ qux => 42 }]
            }
         ```
         And now query B is executed, updating the cache to:
         ```
            foo:1 => {
                baz => [{ qan => 42 }]
            }
         ```
         So we go to update query A's response with the new data in the cache, but `qux` isn't present on `baz`!
         
         What do we do here? We should handle this.
         */
       
    }
}
