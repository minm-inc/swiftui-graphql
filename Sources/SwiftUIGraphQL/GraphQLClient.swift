//
//  GraphQLClient.swift
//  
//
//  Created by Luke Lau on 24/06/2021.
//

import Foundation
import Combine
import SwiftUI

public class GraphQLClient: ObservableObject {
    let cache = Cache()

    let transport: any Transport
    let scalarDecoder: any ScalarDecoder
    let errorCallback: (@MainActor (any Error) -> Bool)?

    /// A convenience method for creating a client with a ``HTTPTransport``
    public convenience init(endpoint: URL) {
        self.init(transport: HTTPTransport(endpoint: endpoint))
    }

    public init(transport: any Transport,
                onError errorCallback: (@MainActor (any Error) -> Bool)? = nil,
                scalarDecoder: ScalarDecoder = FoundationScalarDecoder()) {
        self.transport = transport
        self.errorCallback = errorCallback
        self.scalarDecoder = scalarDecoder
    }
    
    /// All requests to the server within a ``GraphQLClient`` should go through here, where it takes care of updating the cache and stuff.
    func query(query: String, selection: ResolvedSelection<String>, variables: [String: Value]?, cacheUpdater: Cache.Updater? = nil) async throws -> Value {
        do {
            let response = try await transport.makeRequest(query: query,
                                                           variables: variables ?? [:],
                                                           response: Value.self)
            guard case .data(.object(let incoming)) = response else {
                throw GraphQLRequestError.invalidGraphQLResponse
            }
            
            let selection = substituteVariables(in: selection, variableDefs: variables ?? [:])
            await cache.mergeCache(incoming: incoming, selection: selection, updater: cacheUpdater)
            
            return .object(incoming)
        } catch {
            let shouldRetry = await MainActor.run {
                errorCallback?(error) ?? false
            }
            if shouldRetry {
                return try await self.query(query: query,
                                            selection: selection,
                                            variables: variables,
                                            cacheUpdater: cacheUpdater)
            } else {
                throw error
            }
        }
    }
    
    
    public func query<T: Queryable>(_ queryable: T.Type, variables: T.Variables) async throws -> T {
        let decodedData = try await query(query: T.query, selection: T.selection, variables: variablesToObject(variables))
        // Use a try! here because failing to decode a Queryable from a Value is a programming error
        return try! ValueDecoder(scalarDecoder: scalarDecoder).decode(T.self, from: decodedData)
    }
}


func variablesToObject<Variables: Encodable>(_ variables: Variables) -> [String: Value]? {
    let res: [String: Value]?
    let variableValue: Value = try! ValueEncoder().encode(variables)
    switch variableValue {
    case .object(let obj):
        res = ObjectKey.convert(object: obj)
    case .null:
        res = nil
    default:
        fatalError("Invalid variables type")
    }
    return res
}


public class CacheTracked<Fragment: Cacheable>: ObservableObject {
    @Published public private(set) var fragment: Fragment
    private var cancellable: AnyCancellable? = nil
    public init(fragment: Fragment, variableDefs: [String: Value], client: GraphQLClient) {
        self.fragment = fragment
        cancellable = client.cache.publisher.receive(on: RunLoop.main).sink { (changedKeys, store) in
            let cacheKey = CacheKey(type: fragment.__typename, id: fragment.id)
            let cacheObject = store[cacheKey]!
            let selection = substituteVariables(in: Fragment.selection, variableDefs: variableDefs)
            let value = value(from: .object(cacheObject), selection: selection, cacheStore: store)
            self.fragment = try! ValueDecoder(scalarDecoder: client.scalarDecoder).decode(Fragment.self, from: value)
        }
    }
    
    /// Initializes a static fragment definition. Useful for in testing.
    public init(fragment: Fragment) {
        self.fragment = fragment
    }
}

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
        func makeRequest<T: Decodable>(query: String, variables: [String : Value], response: T.Type) async throws -> GraphQLResponse<T> {
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

private class PlaceholderGraphQLClient: GraphQLClient {
    struct PlaceholderTransport: Transport {
        func makeRequest<T: Decodable>(query: String, variables: [String : Value]?, response: T.Type) async throws -> GraphQLResponse<T> {
            fatalError("You need to set \\.graphqlClient somewhere in the environment hierarchy!")
        }
    }
    init() { super.init(transport: PlaceholderTransport()) }
}

struct GraphQLClientKey: EnvironmentKey {
    static var defaultValue: GraphQLClient = PlaceholderGraphQLClient()
}

public extension EnvironmentValues {
    var graphqlClient: GraphQLClient {
        get { self[GraphQLClientKey.self] }
        set { self[GraphQLClientKey.self] = newValue }
    }
}

public enum GraphQLRequestError: Error {
    /// There were errors returned in the GraphQL response
    case graphqlError([GraphQLError])
    /// The server returned a badly-formed response
    case invalidGraphQLResponse
}
