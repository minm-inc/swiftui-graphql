import ArgumentParser
import SwiftUIGraphQL
import Foundation
import GraphQL

@main
struct DownloadSchema: AsyncParsableCommand {
    @Option(help: "URL to GraphQL endpoint to download the schema from", transform: {
        if let url = URL(string: $0) {
            return url
        } else {
            throw ValidationError("Couldn't parse URL")
        }
    })
    var endpoint: URL
    
    @Option(help: "Path to download the schema to")
    var output: String
    
    mutating func run() async throws {
        let queryRequest = GraphQLRequest(query: getIntrospectionQuery(specifiedByURL: true))
        let introspection = try await makeRequest(queryRequest, response: IntrospectionQuery.self, endpoint: endpoint)
        try JSONEncoder().encode(introspection).write(to: URL(fileURLWithPath: output))
    }
}
