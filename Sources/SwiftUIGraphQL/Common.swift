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

public protocol Cacheable: Codable, Selectable, Identifiable, Hashable {
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

public protocol Operation: Codable, Selectable {
    static var query: String { get }
    associatedtype Variables = NoVariables where Variables: Encodable & Equatable
}

public protocol QueryOperation: Operation {}

public protocol MutationOperation: Operation {}
