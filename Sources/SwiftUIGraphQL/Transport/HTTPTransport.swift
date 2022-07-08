import Foundation


/// Implementation of the HTTP transport according to the latest [GraphQL Over HTTP spec](https://github.com/graphql/graphql-over-http/blob/main/spec/GraphQLOverHTTP.md)
public struct HTTPTransport: Transport {
    let endpoint: URL
    let urlSession: URLSession
    let headerCallback: () -> [String: String]
    public init(endpoint: URL, urlSession: URLSession = .shared, headerCallback: @escaping () -> [String : String] = { [:] }) {
        self.endpoint = endpoint
        self.urlSession = urlSession
        self.headerCallback = headerCallback
    }

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

    public func makeRequest<T: Decodable>(query: String, variables: [String : Value], response: T.Type) async throws -> GraphQLResponse<T> {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (headerField, header) in headerCallback() {
            request.setValue(header, forHTTPHeaderField: headerField)
        }
        let graphqlRequest = GraphQLRequest(query: query, variables: variables)
        request.httpBody = try! JSONEncoder().encode(graphqlRequest)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await urlSession.data(for: request)
        let httpResponse = response as! HTTPURLResponse
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw HTTPTransportError.invalidHTTPResponse(httpResponse)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GraphQLResponse<T>.self, from: data)
    }

    public enum HTTPTransportError: Error {
        /// A non 2xx HTTP response was received from the server (i.e. you may need to authenticate, the endpoint is incorrect etc.)
        case invalidHTTPResponse(HTTPURLResponse)
    }
}
