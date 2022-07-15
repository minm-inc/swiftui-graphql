public protocol Transport {
    func makeRequest<T: Decodable>(query: String, variables: [String: Value]?, response: T.Type) async throws -> GraphQLResponse<T>
}

/// A well-formed GraphQL response, as defined per the specification
public enum GraphQLResponse<T: Decodable>: Decodable {
    case data(T)
    case errors(T?, errors: [GraphQLError])
    enum CodingKeys: CodingKey {
        case data, errors
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let data = try! container.decodeIfPresent(T.self, forKey: .data)
        let errors = try! container.decodeIfPresent([GraphQLError].self, forKey: .errors)
        if let errors {
            self = .errors(data, errors: errors)
        } else if let data {
            self = .data(data)
        } else {
            throw GraphQLRequestError.invalidGraphQLResponse
        }
    }
}

public struct GraphQLError: Decodable {
    public let message: String
    public let locations: [Location]?
    public struct Location: Decodable {
        public let line, column: Int
    }
    // TODO: Path segment
}
