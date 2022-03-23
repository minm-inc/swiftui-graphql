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

public protocol Cacheable: Codable, Identifiable {
    var __typename: String { get }
    var id: String { get }
}

public enum TypenameCodingKeys: CodingKey {
    case __typename
}

public typealias ID = String

public protocol Queryable: Codable {
    static var query: String { get }
    static var selections: [ResolvedSelection<String>] { get }
    associatedtype Variables = NoVariables where Variables: Encodable & Equatable
}
