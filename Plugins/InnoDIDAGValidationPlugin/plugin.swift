import Foundation
import PackagePlugin

@main
struct InnoDIDAGValidationPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard target is SourceModuleTarget else {
            return []
        }

        // Opt-out hook for consumers that intentionally skip the build-time
        // DAG gate (PoCs, fast iteration loops, or builds running on a
        // shared volume that already runs validation in a separate CI job).
        // Production CI must leave the variable unset so the gate runs.
        if let optOut = ProcessInfo.processInfo.environment["INNODI_DISABLE_BUILD_VALIDATION"],
           ["1", "true", "yes"].contains(
               optOut.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
           ) {
            return []
        }

        let coordinator = try context.tool(named: "InnoDI-DAGValidationCoordinator")
        let outputDirectory = context.pluginWorkDirectoryURL
        let rootPath = context.package.directoryURL.path(percentEncoded: false)

        return [
            .buildCommand(
                displayName: "Validate InnoDI DAG for \(target.name)",
                executable: coordinator.url,
                arguments: [
                    "--root", rootPath,
                    "--output-dir", outputDirectory.path(percentEncoded: false),
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
        // Explicit safety-net for validationInputFiles; FileManager hidden-file skipping is the primary filter.
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

        var seenInputPaths = Set<String>()
        return inputs
            .filter { seenInputPaths.insert($0.path(percentEncoded: false)).inserted }
            .sorted { $0.path(percentEncoded: false) < $1.path(percentEncoded: false) }
    }
}
