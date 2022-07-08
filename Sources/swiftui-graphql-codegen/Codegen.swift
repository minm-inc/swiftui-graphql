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
import SwiftUIGraphQL
import Codegen

/// Helper to print to stderr
struct StandardError: TextOutputStream {
    mutating func write(_ string: String) {
      for byte in string.utf8 { putc(numericCast(byte), stderr) }
    }
}
var standardError = StandardError()

@main
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
        if schema.host != nil {
            let transport = HTTPTransport(endpoint: schema)
            let response = try await transport.makeRequest(query: getIntrospectionQuery(specifiedByURL: true),
                                                           variables: [:],
                                                           response: IntrospectionQuery.self)
            guard case .data(let introspection) = response else { fatalError("An error ocrred whilst introspecting the schema") }
            return try buildClientSchema(introspection: introspection)
        } else {
            let url = URL(fileURLWithPath: schema.absoluteString)
            if url.pathExtension == "json" {
                let introspection = try JSONDecoder().decode(IntrospectionQuery.self, from: Data(contentsOf: url))
                return try buildClientSchema(introspection: introspection)
            } else {
                let _ = try parse(contents: String(contentsOf: url), filename: url.lastPathComponent)
                // TODO: Implement buildASTSchema in graphql-swift
                fatalError("TODO")
            }
        }
    }
    
    @Option(name: [.long, .customShort("C")], help: "The directory to search for other .graphql files in")
    var projectDirectory: String?
    
    @ArgumentParser.Argument(help: "The .graphql file to generate Swift code for")
    var input: String?
    static var configuration = CommandConfiguration(
        abstract: "Generate Swift code for a query"
    )
    
    private func collectGlobalFragmentDefinitions(schema: GraphQLSchema, input: String) throws -> [FragmentDefinition] {
        let projectDirectory = projectDirectory.map(URL.init(string:)).map { $0! } ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let enumerator = FileManager.default.enumerator(at: projectDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)!
        
        var definitions: [FragmentDefinition] = []
        // Note: Don't bother collecting global fragments from the current input file
        for case let fileURL as URL in enumerator where fileURL != URL(fileURLWithPath: input) {
            let isDirectory = try fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory
            if let isDirectory = isDirectory, isDirectory { continue }
            if fileURL.pathExtension == "graphql" {
                var document = try parse(contents: String(contentsOf: fileURL), filename: fileURL.relativeString)
                document = attachCacheableFields(schema: schema, document: document)
                definitions += fragmentDefinitions(from: document)
            }
        }
        return definitions
    }
    
    /// Print the errors in a xcode friendly format:
    /// `{full_path_to_file}{:line}{:character}: {error,warning}: {content}`
    private func printXcodeError(_ e: GraphQL.GraphQLError) {
        let lineStr: String
        let input = e.source!.name
        if let location = e.locations.first {
            lineStr = "\(input):\(location.line):\(location.column)"
        } else {
            lineStr = "\(input)"
        }
        print("\(lineStr): error: \(e)", to: &standardError)
    }
    
    private func parse(contents: String, filename: String) throws -> GraphQL.Document {
        do {
            let source = GraphQL.Source(body: contents, name: filename)
            return try GraphQL.parse(source: source)
        } catch let error as GraphQL.GraphQLError {
            printXcodeError(error)
            Foundation.exit(1)
        }
    }
    
    mutating func run() async throws {
        let schema = try await loadSchema()
        
        var output = FileOutputStream(path: output)
        
        if let input {
            // If an input was specified, we're generating the types for that documents
            let document = try parse(contents: String(contentsOfFile: input), filename: input)
            
            let globalFragments = try collectGlobalFragmentDefinitions(schema: schema, input: input)
            
            // Need to validate document as if all the other global fragments were in it
            var documentWithGlobalFragments = document
            documentWithGlobalFragments.definitions += globalFragments.map { .executableDefinition(.fragment($0)) }
            
            let validationErrors = GraphQL.validate(schema: schema, ast: documentWithGlobalFragments)
            if !validationErrors.isEmpty {
                validationErrors.forEach(printXcodeError)
                Foundation.exit(1)
            }
            generateDocument(document, schema: schema, globalFragments: globalFragments)
                .write(to: &output)
        } else {
            // Otherwise, we're generating the enum types/input object types for the schema
            genSourceFileWithImports(imports: [], decls: genEnums(schema: schema))
                .write(to: &output)
        }
    }
    
    struct FileOutputStream: TextOutputStream {
        private let handle: FileHandle
        init(path: String?) {
            if let path = path {
                let url = URL(fileURLWithPath: path)
                if !FileManager.default.createFile(atPath: path, contents: nil) {
                    print("Warning: Couldn't create file at path \(path), attempting to write anyway", to: &standardError)
                }
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
