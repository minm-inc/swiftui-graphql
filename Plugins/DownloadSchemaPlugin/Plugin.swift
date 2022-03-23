import PackagePlugin
import Foundation
@main struct DownloadSchemaPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) throws {
        let schema = "http://localhost:3000/graphql"
        let tool = try context.tool(named: "DownloadSchema")
        try Process.run(URL(fileURLWithPath: tool.path.string), arguments: [
            "--endpoint",
            schema,
            "--output",
            context.package.directory.appending(subpath: "schema.json").string
        ]).waitUntilExit()
    }
}
