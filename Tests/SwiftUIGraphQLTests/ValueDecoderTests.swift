import XCTest
@testable import SwiftUIGraphQL

final class ValueDecoderTests: XCTestCase {
    let valueDecoder = ValueDecoder(scalarDecoder: FoundationScalarDecoder())

    func testDecodingObjects() {
        struct Test1: Equatable, Decodable {
            struct Foo: Equatable, Decodable {
                let bar: String
            }
            let foo: Foo
        }

        let res = try! valueDecoder.decode(Test1.self, from: .object([
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

        let res = try! valueDecoder.decode(Test1.self, from: .object([
            "strings": .list([.string("hello"), .string("world")])
        ]))
        XCTAssertEqual(Test1(strings: ["hello", "world"]), res)
    }

    func testCodingPathInError() {
        struct Foo: Decodable {
            let bar: Bar
            struct Bar: Decodable {
                let baz: [Baz]
                struct Baz: Decodable {
                    let x: Double
                }
            }
        }
        let val: Value = [
            "bar": [
                "baz": [
                    ["x": 1],
                    ["x": 2]
                ]
            ]
        ]
        XCTAssertThrowsError(try valueDecoder.decode(Foo.self, from: val)) { error in
            guard case let .typeMismatch(type, context) = error as? DecodingError else {
                XCTFail("asdf")
                return
            }
            XCTAssert(Double.self == type)
            XCTAssertEqual(context.codingPath.map { $0.stringValue }, ["bar", "baz", "Index 0", "x"])
        }
    }
}
