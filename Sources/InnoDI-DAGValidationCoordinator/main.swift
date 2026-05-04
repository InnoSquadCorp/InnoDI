import Foundation
import InnoDIBuildSupport

struct CoordinatorArguments {
    let rootPath: String
    let toolPath: String?
    let stateDirectoryPath: String
    let outputDirectoryPath: String
}

enum CoordinatorExitCode {
    static let failure: Int32 = 1
}

do {
    let arguments = try parseArguments()
    let lockPolicy = ValidationCoordinatorLockPolicy(
        environment: ProcessInfo.processInfo.environment
    )
    let outcome = try await ValidationCoordinator.coordinate(
        rootPath: arguments.rootPath,
        toolPath: arguments.toolPath ?? "",
        stateDirectoryPath: arguments.stateDirectoryPath,
        outputDirectoryPath: arguments.outputDirectoryPath,
        lockPolicy: lockPolicy
    )

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

private func parseArguments() throws -> CoordinatorArguments {
    let args = Array(CommandLine.arguments.dropFirst())
    var rootPath: String?
    var toolPath: String?
    var stateDirectoryPath: String?
    var outputDirectoryPath: String?
    var index = 0

    func requireValue(for option: String) throws -> String {
        guard index + 1 < args.count else {
            throw CoordinatorArgumentError.missingValue(option: option)
        }
        let value = args[index + 1]
        guard !value.hasPrefix("-") else {
            throw CoordinatorArgumentError.missingValue(option: option)
        }
        return value
    }

    while index < args.count {
        let option = args[index]
        switch option {
        case "--root":
            rootPath = try requireValue(for: option)
            index += 2
        case "--tool":
            toolPath = try requireValue(for: option)
            index += 2
        case "--state-dir":
            stateDirectoryPath = try requireValue(for: option)
            index += 2
        case "--output-dir":
            outputDirectoryPath = try requireValue(for: option)
            index += 2
        default:
            throw CoordinatorArgumentError.unknownOption(option)
        }
    }

    guard let rootPath, let stateDirectoryPath, let outputDirectoryPath else {
        throw CoordinatorArgumentError.missingRequiredArguments
    }

    return CoordinatorArguments(
        rootPath: rootPath,
        toolPath: toolPath,
        stateDirectoryPath: stateDirectoryPath,
        outputDirectoryPath: outputDirectoryPath
    )
}

enum CoordinatorArgumentError: LocalizedError {
    case missingValue(option: String)
    case unknownOption(String)
    case missingRequiredArguments

    var errorDescription: String? {
        switch self {
        case let .missingValue(option):
            return "Option \(option) requires a value."
        case let .unknownOption(option):
            return "Unknown option \(option)."
        case .missingRequiredArguments:
            return "Required options: --root, --state-dir, --output-dir. Optional compatibility input: --tool <path>."
        }
    }
}
