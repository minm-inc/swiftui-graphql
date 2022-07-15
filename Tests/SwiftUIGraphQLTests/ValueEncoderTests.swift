import XCTest
@testable import SwiftUIGraphQL

final class ValueEncoderTests: XCTestCase {
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
