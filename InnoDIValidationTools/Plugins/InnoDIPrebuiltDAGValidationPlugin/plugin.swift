import Foundation
import PackagePlugin

@main
struct InnoDIPrebuiltDAGValidationPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard target is SourceModuleTarget else {
            return []
        }

        if let optOut = ProcessInfo.processInfo.environment["INNODI_DISABLE_BUILD_VALIDATION"],
           ["1", "true", "TRUE", "yes", "YES"].contains(optOut) {
            return []
        }

        let coordinator = try context.tool(named: "InnoDIPrebuiltDAGValidationCoordinator")
        let outputDirectory = context.pluginWorkDirectoryURL
        let rootPath = context.package.directoryURL.path
        let sharedStateDirectory = sharedValidationStateDirectory(for: outputDirectory)

        return [
            .buildCommand(
                displayName: "Validate InnoDI DAG for \(target.name) (prebuilt)",
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

    private func sharedValidationStateDirectory(for outputDirectory: URL) -> URL {
        let components = outputDirectory.pathComponents
        if let outputsIndex = components.lastIndex(of: "outputs"),
           outputsIndex + 1 < components.count {
            return URL(
                fileURLWithPath: NSString.path(
                    withComponents: Array(components.prefix(outputsIndex + 2))
                ),
                isDirectory: true
            )
            .appending(path: "innodi-dag-validation-state", directoryHint: .isDirectory)
        }

        return outputDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "innodi-dag-validation-state", directoryHint: .isDirectory)
    }
}
