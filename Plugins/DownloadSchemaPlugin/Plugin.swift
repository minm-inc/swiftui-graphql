import PackagePlugin
import Foundation
@main struct DownloadSchemaPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) throws {
        let tool = try context.tool(named: "swiftui-graphql-download-schema")
        try Process.run(URL(fileURLWithPath: tool.path.string), arguments: [
            "--output",
            context.package.directory.appending(subpath: "schema.json").string
        ] + arguments.dropFirst(2)).waitUntilExit()
    }
}
