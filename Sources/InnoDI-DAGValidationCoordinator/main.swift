import Foundation
import InnoDIBuildSupport

enum CoordinatorExitCode {
    static let failure: Int32 = 1
}

do {
    let arguments = try parseArguments()
    let lockPolicy = ValidationCoordinatorLockPolicy(
        environment: ProcessInfo.processInfo.environment
    )
    let sharedStateDirectoryPath = arguments.stateDirectoryPath
        ?? sharedValidationStateDirectory(
        forPluginOutputDirectory: URL(fileURLWithPath: arguments.outputDirectoryPath, isDirectory: true)
    ).path(percentEncoded: false)
    let outcome: ValidationExecutionOutcome
    switch arguments.input {
    case .rootPath(let rootPath):
        outcome = try await ValidationCoordinator.coordinate(
            rootPath: rootPath,
            toolPath: arguments.toolPath,
            stateDirectoryPath: sharedStateDirectoryPath,
            outputDirectoryPath: arguments.outputDirectoryPath,
            lockPolicy: lockPolicy
        )
    case .analysisManifestPath(let manifestPath):
        outcome = try await ValidationCoordinator.coordinate(
            analysisManifestPath: manifestPath,
            sharedStateDirectoryPath: sharedStateDirectoryPath,
            outputDirectoryPath: arguments.outputDirectoryPath,
            lockPolicy: lockPolicy
        )
    }

    if outcome.result.exitCode != 0 || !outcome.wasCached {
        if !outcome.result.stdout.isEmpty {
            FileHandle.standardOutput.write(Data(outcome.result.stdout.utf8))
        }
        if !outcome.result.stderr.isEmpty {
            FileHandle.standardError.write(Data(outcome.result.stderr.utf8))
        }
    }
    if let verboseSummary = outcome.verboseSummary {
        FileHandle.standardError.write(Data(verboseSummary.utf8))
    }

    Foundation.exit(outcome.result.exitCode)
} catch {
    fputs("Error: \(error)\n", stderr)
    Foundation.exit(CoordinatorExitCode.failure)
}

private func parseArguments() throws -> ValidationCoordinatorArguments {
    try parseValidationCoordinatorArguments()
}
