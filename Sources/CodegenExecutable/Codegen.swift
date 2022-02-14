//
//  Codegen.swift
//  
//
//  Created by Luke Lau on 13/10/2021.
//

import ArgumentParser
import Foundation
import GraphQL
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftUIGraphQL
import Codegen

/// Helper to print to stderr
struct StandardError: TextOutputStream {
    mutating func write(_ string: String) {
      for byte in string.utf8 { putc(numericCast(byte), stderr) }
    }
}
var standardError = StandardError()

@main enum Main: AsyncMain {
    typealias Command = Codegen
}

struct Codegen: AsyncParsableCommand {
    
    @Option(help: "Path to the schema.json file, or URL to the endpoint to perform an introspection query on", transform: {
        if let url = URL(string: $0) {
            return url
        } else {
            throw ValidationError("Couldn't parse URL")
        }
    })
    var schema: URL
    
    @Option(help: "The path to write the generate Swift code to. If not specified, write to stdout")
    var output: String?
    
    func loadSchema() async throws -> GraphQLSchema {
        let queryRequest = QueryRequest(query: getIntrospectionQuery())
        let introspection: IntrospectionQuery
        if schema.host != nil {
            introspection = try await makeRequest(queryRequest, endpoint: schema)
        } else {
            let url = URL(fileURLWithPath: schema.absoluteString)
            introspection = try JSONDecoder().decode(IntrospectionQuery.self, from: Data(contentsOf: url))
        }
        return try buildClientSchema(introspection: introspection)
    }
    
    @ArgumentParser.Argument(help: "The .graphql file to generate Swift code for")
    var input: String
    static var configuration = CommandConfiguration(
        abstract: "Generate Swift code for a query"
    )
    
    mutating func run() async throws {
        let schema = try await loadSchema()
        
        let source = GraphQL.Source(body: try String(contentsOfFile: input), name: input)
        let document: Document
        
        /// Print the errors in a xcode friendly format:
        /// `{full_path_to_file}{:line}{:character}: {error,warning}: {content}`
        func printXcodeError(_ e: GraphQL.GraphQLError) {
            let lineStr: String
            if let location = e.locations.first {
                lineStr = "\(input):\(location.line):\(location.column)"
            } else {
                lineStr = "\(input)"
            }
            print("\(lineStr): error: \(e)", to: &standardError)
        }
        
        do {
            document = try GraphQL.parse(source: source)
        } catch let error as GraphQL.GraphQLError {
            printXcodeError(error)
            Foundation.exit(1)
        }
        
        let validationErrors = GraphQL.validate(schema: schema, ast: document)
        if !validationErrors.isEmpty {
            validationErrors.forEach(printXcodeError)
            Foundation.exit(1)
        }
        
        var output = FileOutputStream(path: output)
        generateCode(document: document, schema: schema).write(to: &output)
    }
    
    struct FileOutputStream: TextOutputStream {
        private let handle: FileHandle
        init(path: String?) {
            if let path = path {
                let url = URL(fileURLWithPath: path)
                _ = FileManager.default.createFile(atPath: path, contents: nil)
                handle = try! FileHandle(forWritingTo: url)
            } else {
                handle = FileHandle.standardOutput
            }
        }
        
        func write(_ string: String) {
            try! handle.write(contentsOf: string.data(using: .utf8)!)
        }
    }
}
