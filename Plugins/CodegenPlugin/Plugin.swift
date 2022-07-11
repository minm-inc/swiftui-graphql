import Foundation
import PackagePlugin
import XcodeProjectPlugin


@main struct CodegenPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let tool = try context.tool(named: "swiftui-graphql-codegen")
        guard let target = target as? SourceModuleTarget else {
            return []
        }
        return createCommands(tool: tool,
                              schemaPath: target.directory.appending(subpath: "schema.json"),
                              pluginWorkDirectory: context.pluginWorkDirectory,
                              graphqlFiles: target.sourceFiles(withSuffix: "graphql"))
    }

    func createCommands(tool: PluginContext.Tool, schemaPath: Path, pluginWorkDirectory: Path, graphqlFiles: some Sequence<File>) -> [Command] {
        let graphqlCommands = graphqlFiles.map { inputFile in
            let outputPath = pluginWorkDirectory.appending(inputFile.path.stem + ".swift")
            return Command.buildCommand(
                displayName: "Generate GraphQL types for \(inputFile.path.lastComponent)",
                executable: tool.path,
                arguments: ["--output", outputPath.string, "--schema", schemaPath.string, inputFile.path.string],
                inputFiles: [inputFile.path, schemaPath],
                outputFiles: [outputPath])
        }
        let schemaOutputPath = pluginWorkDirectory.appending("schema.swift")
        let schemaTypesCommand = Command.buildCommand(displayName: "Generate GraphQL enum types for \(schemaPath)",
                                                      executable: tool.path,
                                                      arguments: ["--output", schemaOutputPath, "--schema", schemaPath.string],
                                                      inputFiles: [schemaPath],
                                                      outputFiles: [schemaOutputPath])
        return [schemaTypesCommand] + graphqlCommands
    }
}

extension CodegenPlugin: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        createCommands(tool: try context.tool(named: "swiftui-graphql-codegen"),
                       schemaPath: context.xcodeProject.directory.appending(subpath: "schema.json"),
                       pluginWorkDirectory: context.pluginWorkDirectory,
                       graphqlFiles: target.inputFiles.filter { $0.type == .source && $0.path.extension == "graphql" })
    }
}
