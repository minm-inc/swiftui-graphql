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
}
