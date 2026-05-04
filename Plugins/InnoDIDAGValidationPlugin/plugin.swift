import Foundation
import PackagePlugin

@main
struct InnoDIDAGValidationPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard target is SourceModuleTarget else {
            return []
        }

        let coordinator = try context.tool(named: "InnoDI-DAGValidationCoordinator")
        let outputDirectory = context.pluginWorkDirectoryURL
        let rootPath = context.package.directoryURL.path
        let sharedStateDirectory = context.package.directoryURL
            .appending(path: ".build", directoryHint: .isDirectory)
            .appending(path: "innodi-dag-validation", directoryHint: .isDirectory)

        return [
            .prebuildCommand(
                displayName: "Validate InnoDI DAG for \(target.name)",
                executable: coordinator.url,
                arguments: [
                    "--root", rootPath,
                    "--state-dir", sharedStateDirectory.path,
                    "--output-dir", outputDirectory.path,
                ],
                outputFilesDirectory: outputDirectory
            )
        ]
    }
}
