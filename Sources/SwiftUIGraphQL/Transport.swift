import Foundation

/// Stuff to do with talking to the server etc.

public struct GraphQLRequest: Encodable {
    let query: String
    let operationName: String?
    let variables: [String: Value]?
    public init(query: String, operationName: String? = nil, variables: [String: Value]? = nil) {
        self.query = query
        self.operationName = operationName
        self.variables = variables
    }
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
        let data = try container.decode(T?.self, forKey: .data)
        let errors = try container.decode([GraphQLError]?.self, forKey: .errors)
        if let errors {
            self = .errors(data, errors: errors)
        } else if let data {
            self = .data(data)
        } else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Neither data nor errors nor were present in the GraphQL response"))
        }
    }
}

public struct GraphQLError: Decodable {
    public let message: String
}

/// Makes a standalone request, throwing if there any errors at either the transport or GraphQL level.
public func makeRequest<T: Decodable>(_ graphqlRequest: GraphQLRequest,
                                      response: T.Type,
                                      endpoint: URL,
                                      urlSession: URLSession = .shared,
                                      headers: [String: String] = [:]) async throws -> T {
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    for (headerField, header) in headers {
        request.setValue(header, forHTTPHeaderField: headerField)
    }
    request.httpBody = try! JSONEncoder().encode(graphqlRequest)
    request.cachePolicy = .reloadIgnoringLocalCacheData
    
    let (data, response) = try await urlSession.data(for: request)
    let httpResponse = response as! HTTPURLResponse
    guard (200..<300).contains(httpResponse.statusCode) else {
        throw GraphQLRequestError.invalidHTTPResponse(httpResponse)
    }
    
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    switch try decoder.decode(GraphQLResponse<T>.self, from: data) {
    case .errors(_, let errors):
        throw GraphQLRequestError.graphqlError(errors)
    case .data(let data):
        return data
    }
}

public enum GraphQLRequestError: Error {
    /// There were errors returned in the GraphQL response
    case graphqlError([GraphQLError])
    /// A non 2xx HTTP response was received from the server (i.e. you may need to authenticate, the endpoint is incorrect etc.)
    case invalidHTTPResponse(HTTPURLResponse)
}
