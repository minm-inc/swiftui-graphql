import SwiftUIGraphQL
protocol ContainsFooFragment {
    var z: Int? { get }
    var __fooFragment: FooFragment<X, Y> { get }
    associatedtype X: FooFragmentX
    associatedtype Y: FooFragmentY
}

enum FooFragment<X: FooFragmentX, Y: FooFragmentY> {
    case x(X)
    case y(Y)
    case __other
}

protocol FooFragmentX {
    var x1: Int? { get }
    var z: Int? { get }
}

protocol FooFragmentY {
    var y: Int? { get }
    var z: Int? { get }
}

protocol ContainsBarFragment {
    var __barFragment: BarFragment<X> { get }
    associatedtype X: BarFragmentX
}

enum BarFragment<X: BarFragmentX> {
    case x(X)
    case __other
}

protocol BarFragmentX: BazFragment where X2: BarFragmentXX2 {
    var x2: X2? { get }
}

protocol BarFragmentXX2 {
    var b: Int? { get }
}

protocol BazFragment {
    associatedtype X2: BazFragmentX2
    var x2: X2? { get }
}

protocol BazFragmentX2 {
    var a: Int? { get }
}

struct AnonymousQuery: QueryOperation, Codable {
    let iface: Iface?
    enum Iface: Codable, ContainsFooFragment {
        case x(X)
        case y(Y)
        case __other(__Other)
        struct X: Codable, BazFragment, FooFragmentX, BarFragmentX {
            let x1: Int?
            let x2: X2?
            struct X2: Codable, BarFragmentXX2, BazFragmentX2 {
                let b: Int?
                let a: Int?
            }
            let z: Int?
        }
        struct Y: Codable, FooFragmentY {
            let y: Int?
            let z: Int?
        }
        var z: Int? {
            switch self {
            case .x(let x):
                return x.z
            case .y(let y):
                return y.z
            case .__other(let __other):
                return __other.z
            }
        }
        struct __Other: Codable {
            let z: Int?
        }
        var __fooFragment: FooFragment<X, Y> {
            switch self {
            case .x(let x):
                return .x(x)
            case .y(let y):
                return .y(y)
            case .__other:
                return .__other
            }
        }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: TypenameCodingKeys.self)
            let typename = try container.decode(String.self, forKey: .__typename)
            switch typename {
            case "X":
                self = .x(try X(from: decoder))
            case "Y":
                self = .y(try Y(from: decoder))
            default:
                self = .__other(try __Other(from: decoder))
            }
        }
        func encode(to encoder: Encoder) throws {
            switch self {
            case .x(let x):
                try x.encode(to: encoder)
            case .y(let y):
                try y.encode(to: encoder)
            case .__other(let __other):
                try __other.encode(to: encoder)
            }
        }
    }
    static let query = """
 {
iface {
...Foo
}
}
fragment Bar on Interface {
... on X {
x2 {
b
}
...Baz
}
}
fragment Baz on X {
x2 {
a
}
}
fragment Foo on Interface {
... on X {
x1
}
... on Y {
y
}
...Bar
z
}
"""
}
