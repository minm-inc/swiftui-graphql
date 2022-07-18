import SwiftUIGraphQL
struct AnonymousQuery: QueryOperation, Codable, FooFragment, BarFragment, BazFragment {
    let a: A?
    struct A: Codable, FooFragmentA, BarFragmentA {
        let b1: Int?
        let b2: Int?
    }
    let b: B?
    struct B: Codable, BazFragmentB {
        let b1: Int?
    }
    static let query = """
 {
...Foo
...Bar
...Baz
}
fragment Bar on Query {
a {
b2
}
}
fragment Baz on Query {
b: a {
b1
}
}
fragment Foo on Query {
a {
b1
}
}
"""
}

protocol FooFragment {
    associatedtype A: FooFragmentA
    var a: A? { get }
}

protocol FooFragmentA {
    var b1: Int? { get }
}

protocol BarFragment {
    associatedtype A: BarFragmentA
    var a: A? { get }
}

protocol BarFragmentA {
    var b2: Int? { get }
}

protocol BazFragment {
    associatedtype B: BazFragmentB
    var b: B? { get }
}

protocol BazFragmentB {
    var b1: Int? { get }
}
