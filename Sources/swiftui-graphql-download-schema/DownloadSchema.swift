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
        let transport = HTTPTransport(endpoint: endpoint)
        let response = try await transport.makeRequest(query: getIntrospectionQuery(specifiedByURL: true),
                                                       variables: [:],
                                                       response: IntrospectionQuery.self)
        guard case .data(let introspection) = response else { fatalError("An error ocrred whilst introspecting the schema") }
        try JSONEncoder().encode(introspection).write(to: URL(fileURLWithPath: output))
    }
}
