//import SwiftUIGraphQL
//struct AnonymousQuery: Queryable, Codable, FooFragment {
//    let a: A?
//    struct A: Codable, FooFragmentA, BarFragmentA, BazFragmentA {
//        let a1: Int?
//        let a2: Int?
//    }
//    let b: Int?
//    static let query = """
// {
//...Foo
//}
//fragment Bar on Query {
//b
//...Baz
//}
//fragment Baz on Query {
//a {
//a2
//}
//}
//fragment Foo on Query {
//a {
//a1
//}
//...Bar
//}
//"""
//}
//
//protocol FooFragment: BarFragment where A: FooFragmentA {
//    
//    var a: A? { get }
//    var b: Int? { get }
//}
//
//protocol FooFragmentA {
//    var a1: Int? { get }
//    var a2: Int? { get }
//}
//
//protocol BarFragment: BazFragment where A: BarFragmentA {
//    var b: Int? { get }
//    
//    var a: A? { get }
//}
//
//protocol BarFragmentA {
//    var a2: Int? { get }
//}
//
//protocol BazFragment {
//    associatedtype A: BazFragmentA
//    var a: A? { get }
//}
//
//protocol BazFragmentA {
//    var a2: Int? { get }
//}
