import Foundation

/// A mock ``GraphQLClient`` that can be initialized with a canned JSON response for use in Xcode Previews and testing.
///
/// To use it, set a ``MockGraphQLClient`` as the environment value for the `graphqlClient` environment key.
/// Any ``Query``s in the view hierarchy will then use the response for their ``GraphQLResult``.
///
/// A convenient pattern is to store your prepared mock JSON responses in a folder somewhere in your app, then add it to your target's [development assets](https://developer.apple.com/wwdc19/233?time=984).
/// Then you can access it from the main bundle:
/// ```swift
/// struct Library_Previews: PreviewProvider {
///     static var previews: some View {
///         MyView()
///             .environment(\.graphqlClient,
///                          MockGraphQLClient(from: Bundle.main.url(forResource: "queryResponse",
///                                                                  withExtension: "json")!))
///     }
/// }
/// ```
public class MockGraphQLClient: GraphQLClient {
    private struct MockTransport: Transport {
        func makeRequest<T: Decodable>(query: String, variables: [String : Value]?, response: T.Type) async throws -> GraphQLResponse<T> {
            fatalError()
        }
    }

    @resultBuilder
    public struct MockBuilder {
        public static func buildBlock(_ parts: MockResponse...) -> [ObjectIdentifier: GraphQLResponse<Value>] {
            return parts.reduce(into: [:]) { $0[$1.operation] = $1.response }
        }
    }

    public init(@MockBuilder _ mockResponses: () -> [ObjectIdentifier: GraphQLResponse<Value>]) {
        self.responseMap = mockResponses()
        super.init(transport: MockTransport())
    }

    let responseMap: [ObjectIdentifier: GraphQLResponse<Value>]

    override func makeTransportRequest<T>(_ operation: T.Type, variables: [String : Value]?) async throws -> GraphQLResponse<Value> where T : Operation {
        guard let res = responseMap[ObjectIdentifier(operation)] else {
            fatalError("Missing a mock response for \(operation)")
        }
        return res
    }
}

public struct MockResponse {
    let operation: ObjectIdentifier
    let response: GraphQLResponse<Value>

    /// Create a mock response for the operation type from a JSON file specified at the URL.
    public init<T: Operation>(_ type: T.Type, responseURL: URL) {
        self.operation = ObjectIdentifier(type)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.response = try! decoder.decode(GraphQLResponse<Value>.self, from: Data(contentsOf: responseURL))
    }

    public init<T: Operation>(_ type: T.Type, response: GraphQLResponse<Value>) {
        self.operation = ObjectIdentifier(type)
        self.response = response
    }
}
