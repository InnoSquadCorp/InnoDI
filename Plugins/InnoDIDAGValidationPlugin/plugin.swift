import Foundation
import PackagePlugin

@main
struct InnoDIDAGValidationPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard target is SourceModuleTarget else {
            return []
        }

        let tool = try context.tool(named: "InnoDI-DependencyGraph")
        let outputDirectory = context.pluginWorkDirectoryURL
        let rootPath = context.package.directoryURL.path

        return [
            .prebuildCommand(
                displayName: "Validate InnoDI DAG for \(target.name)",
                executable: tool.url,
                arguments: [
                    "--root", rootPath,
                    "--validate-dag",
                    "--format", "ascii",
                    "--output", outputDirectory.appending(path: "dag-validation-\(target.name).txt").path,
                ],
                outputFilesDirectory: outputDirectory
            )
        ]
    }
}
