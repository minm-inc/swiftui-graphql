import Foundation
import PackagePlugin

@main struct CodegenPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let tool = try context.tool(named: "swiftui-graphql-codegen")
        guard let target = target as? SourceModuleTarget else {
            return []
        }
        let genSourcesDir = context.pluginWorkDirectory.appending("GeneratedSources")
        let schema = "schema.json"
        return target.sourceFiles(withSuffix: "graphql").map { inputFile in
            let outputPath = genSourcesDir.appending(inputFile.path.stem + ".swift")
            return .buildCommand(
                displayName: "Generate GraphQL types for \(inputFile.path.lastComponent)",
                executable: tool.path,
                arguments: ["--output", outputPath.string, "--schema", schema, inputFile.path.string],
                inputFiles: [inputFile.path],
                outputFiles: [outputPath])
        }
    }
}
