import SwiftUIGraphQL
struct AnonymousQuery: QueryOperation, Codable {
    let a: A?
    enum A: Codable {
        case impl(Impl)
        case __other(__Other)
        struct Impl: Codable, FooFragment {
            let b: B?
            struct B: Codable, FooFragmentB {
                let b2: Int?
                let b3: [B3?]?
                struct B3: Codable, FooFragmentBB3 {
                    let c2: Int?
                    let c1: Int?
                    fileprivate func convert() -> AnonymousQuery.A.B.B3 {
                        AnonymousQuery.A.B.B3(c1: c1)
                    }
                }
                let b4: B4?
                enum B4: Codable, ContainsFooFragmentBB4 {
                    case impl2(Impl2)
                    case __other(__Other)
                    struct Impl2: Codable, FooFragmentBB4Impl2 {
                        let d: D?
                        struct D: Codable, FooFragmentBB4Impl2D {
                            let d2: Int?
                            let d1: Int?
                            fileprivate func convert() -> AnonymousQuery.A.Impl.B.B4.D {
                                AnonymousQuery.A.Impl.B.B4.D(d1: d1)
                            }
                            fileprivate func convert() -> AnonymousQuery.A.B.B4.D {
                                AnonymousQuery.A.B.B4.D(d1: d1)
                            }
                        }
                    }
                    var d: D? {
                        switch self {
                        case .impl2(let impl2):
                            return impl2.d.map({ $0.convert() })
                        case .__other(let __other):
                            return __other.d
                        }
                    }
                    struct D: Codable {
                        let d1: Int?
                        fileprivate func convert() -> AnonymousQuery.A.B.B4.D {
                            AnonymousQuery.A.B.B4.D(d1: d1)
                        }
                    }
                    struct __Other: Codable {
                        let d: D?
                    }
                    var __fooFragmentBB4: FooFragmentBB4<Impl2> {
                        switch self {
                        case .impl2(let impl2):
                            return .impl2(impl2)
                        case .__other:
                            return .__other
                        }
                    }
                    fileprivate func convert() -> AnonymousQuery.A.B.B4 {
                        switch self {
                        case .impl2(let impl2):
                            return AnonymousQuery.A.B.B4(d: impl2.d.map({ $0.convert() }))
                        case .__other(let __other):
                            return AnonymousQuery.A.B.B4(d: __other.d.map({ $0.convert() }))
                        }
                    }
                    init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: TypenameCodingKeys.self)
                        let typename = try container.decode(String.self, forKey: .__typename)
                        switch typename {
                        case "Impl2":
                            self = .impl2(try Impl2(from: decoder))
                        default:
                            self = .__other(try __Other(from: decoder))
                        }
                    }
                    func encode(to encoder: Encoder) throws {
                        switch self {
                        case .impl2(let impl2):
                            try impl2.encode(to: encoder)
                        case .__other(let __other):
                            try __other.encode(to: encoder)
                        }
                    }
                }
                let b1: Int?
                fileprivate func convert() -> AnonymousQuery.A.B {
                    AnonymousQuery.A.B(b1: b1,b3: b3.map({ $0.map({ $0.map({ $0.convert() }) }) }),b4: b4.map({ $0.convert() }))
                }
            }
        }
        var b: B? {
            switch self {
            case .impl(let impl):
                return impl.b.map({ $0.convert() })
            case .__other(let __other):
                return __other.b
            }
        }
        struct B: Codable {
            let b1: Int?
            let b3: [B3?]?
            struct B3: Codable {
                let c1: Int?
            }
            let b4: B4?
            struct B4: Codable {
                let d: D?
                struct D: Codable {
                    let d1: Int?
                }
            }
        }
        struct __Other: Codable {
            let b: B?
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
b3 {
c1
}
b4 {
d {
d1
}
}
}
...Foo
}
}
fragment Foo on Impl {
b {
b2
b3 {
c2
}
b4 {
... on Impl2 {
d {
d2
}
}
}
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
    associatedtype B3: FooFragmentBB3
    var b3: [B3?]? { get }
    associatedtype B4: ContainsFooFragmentBB4
    var b4: B4? { get }
}

protocol FooFragmentBB3 {
    var c2: Int? { get }
}

protocol ContainsFooFragmentBB4 {
    var __fooFragmentBB4: FooFragmentBB4<Impl2> { get }
    associatedtype Impl2: FooFragmentBB4Impl2
}

enum FooFragmentBB4<Impl2: FooFragmentBB4Impl2> {
    case impl2(Impl2)
    case __other
}

protocol FooFragmentBB4Impl2 {
    associatedtype D: FooFragmentBB4Impl2D
    var d: D? { get }
}

protocol FooFragmentBB4Impl2D {
    var d2: Int? { get }
}
