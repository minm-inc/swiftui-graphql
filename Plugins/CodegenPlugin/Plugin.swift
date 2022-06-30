import Foundation
import PackagePlugin

@main struct CodegenPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let tool = try context.tool(named: "swiftui-graphql-codegen")
        guard let target = target as? SourceModuleTarget else {
            return []
        }
        let schema = target.directory.appending(subpath: "schema.json")
        let graphqlCommands = target.sourceFiles(withSuffix: "graphql").map { inputFile in
            let outputPath = context.pluginWorkDirectory.appending(inputFile.path.stem + ".swift")
            return Command.buildCommand(
                displayName: "Generate GraphQL types for \(inputFile.path.lastComponent)",
                executable: tool.path,
                arguments: ["--output", outputPath.string, "--schema", schema.string, inputFile.path.string],
                inputFiles: [inputFile.path, schema],
                outputFiles: [outputPath])
        }
        let schemaOutputPath = context.pluginWorkDirectory.appending("schema.swift")
        let schemaTypesCommand = Command.buildCommand(displayName: "Generate GraphQL enum types for \(schema)",
                                                      executable: tool.path,
                                                      arguments: ["--output", schemaOutputPath, "--schema", schema.string],
                                                      inputFiles: [schema],
                                                      outputFiles: [schemaOutputPath])
        return [schemaTypesCommand] + graphqlCommands
    }
}
