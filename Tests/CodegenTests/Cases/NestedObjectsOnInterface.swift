import SwiftUIGraphQL
struct AnonymousQuery: Queryable, Codable {
    let a: A?
    enum A: Codable {
        case impl(Impl)
        case __other(__Other)
        struct Impl: Codable {
            let b: B?
            struct B: Codable {
                let b1: Int?
                let b2: Int?
            }
        }
        struct __Other: Codable {
            let b: B?
            struct B: Codable {
                let b1: Int?
            }
        }
        var b: B? {
            switch self {
            case .impl(let impl):
                return impl.b
            case .__other(let __other):
                return __other.b
            }
        }
        struct B: Codable {
            let b1: Int?
        }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: TypenameCodingKeys.self)
            let typename = try container.decode(String.self, forKey: .__typename)
            switch typename {
            case "Impl":
                self = .impl(try Impl(from: decoder))
            default:
                self = .__other(try __Other(from: decoder))
            }
        }
        func encode(to encoder: Encoder) throws {
            switch self {
            case .impl(let impl):
                try impl.encode(to: encoder)
            case .__other(let __other):
                try __other.encode(to: encoder)
            }
        }
    }
    static let query = """
 {
a {
b {
b1
}
...Foo
}
}
fragment Foo on Impl {
b {
b2
}
}
"""
}

protocol FooFragment {
    associatedtype B: FooFragmentB
    var b: B? { get }
}

protocol FooFragmentB {
    var b2: Int? { get }
}
