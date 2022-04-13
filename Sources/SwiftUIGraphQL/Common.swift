/**
 This contains definitions that are required by codegened code
 */

public struct NoVariables: Encodable, Equatable {
    public init() {}
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encodeNil()
    }
}

public protocol Cacheable: Codable, Selectable, Identifiable {
    var __typename: String { get }
    var id: SwiftUIGraphQL.ID { get }
}

public enum TypenameCodingKeys: CodingKey {
    case __typename
}

public typealias ID = String

public protocol Selectable {
    static var selection: ResolvedSelection<String> { get }
}

public protocol Queryable: Codable, Selectable {
    static var query: String { get }
    associatedtype Variables = NoVariables where Variables: Encodable & Equatable
}
