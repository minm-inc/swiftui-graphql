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
        let response: GraphQLResponse<Value>
        func makeRequest<T: Decodable>(query: String, variables: [String : Value]?, response: T.Type) async throws -> GraphQLResponse<T> {
            self.response as! GraphQLResponse<T>
        }
    }
    /// Create a mock GraphQL client that returns the response from a JSON file specified at the URL.
    public init(from url: URL) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try! decoder.decode(GraphQLResponse<Value>.self, from: Data(contentsOf: url))
        super.init(transport: MockTransport(response: response))
    }

    public init(response: GraphQLResponse<Value>) {
        super.init(transport: MockTransport(response: response))
    }
}
