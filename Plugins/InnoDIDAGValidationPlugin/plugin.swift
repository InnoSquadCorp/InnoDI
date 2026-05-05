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
        let sharedStateDirectory = outputDirectory
            .appending(path: "innodi-dag-validation-state", directoryHint: .isDirectory)

        return [
            .buildCommand(
                displayName: "Validate InnoDI DAG for \(target.name)",
                executable: coordinator.url,
                arguments: [
                    "--root", rootPath,
                    "--state-dir", sharedStateDirectory.path,
                    "--output-dir", outputDirectory.path,
                ],
                inputFiles: validationInputFiles(packageRoot: context.package.directoryURL),
                outputFiles: [
                    outputDirectory.appending(path: "dag-validation-stamp.txt"),
                    outputDirectory.appending(path: "dag-validation-metrics.json"),
                    outputDirectory.appending(path: "dag-validation-summary.md"),
                ]
            )
        ]
    }

    private func validationInputFiles(packageRoot: URL) -> [URL] {
        let fileManager = FileManager.default
        let excludedDirectories: Set<String> = [
            ".build",
            ".git",
            ".swiftpm",
        ]

        guard let enumerator = fileManager.enumerator(
            at: packageRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return [packageRoot.appending(path: "Package.swift")]
        }

        var inputs: [URL] = [
            packageRoot.appending(path: "Package.swift"),
        ]

        for case let url as URL in enumerator {
            if excludedDirectories.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }

            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey]) else {
                continue
            }
            if values.isDirectory == true {
                continue
            }
            guard values.isRegularFile == true else {
                continue
            }

            if url.pathExtension == "swift" || url.lastPathComponent == "Package.swift" {
                inputs.append(url)
            }
        }

        return Array(Set(inputs)).sorted { $0.path < $1.path }
    }
}
