import Foundation

package enum ValidationCoordinatorInput: Equatable, Sendable {
    case rootPath(String)
    case analysisManifestPath(String)
}

package struct ValidationCoordinatorArguments: Equatable, Sendable {
    package let input: ValidationCoordinatorInput
    package let toolPath: String?
    package let stateDirectoryPath: String?
    package let outputDirectoryPath: String
}

package enum ValidationCoordinatorArgumentError:
    LocalizedError,
    Equatable
{
    case missingValue(option: String)
    case unknownOption(String)
    case duplicateOption(String)
    case conflictingWorkspaceInputs
    case externalToolUnsupportedForManifest
    case missingRequiredArguments

    package var errorDescription: String? {
        switch self {
        case .missingValue(let option):
            return "Option \(option) requires a value."
        case .unknownOption(let option):
            return "Unknown option \(option)."
        case .duplicateOption(let option):
            return "Option \(option) may only be provided once."
        case .conflictingWorkspaceInputs:
            return "Options --root and --analysis-manifest are mutually exclusive."
        case .externalToolUnsupportedForManifest:
            return "Option --tool is not supported with --analysis-manifest; manifest-backed validation runs in process."
        case .missingRequiredArguments:
            return "Required options: exactly one of --root <path> or --analysis-manifest <path>, plus --output-dir <path>."
        }
    }
}

package func parseValidationCoordinatorArguments(
    _ rawArguments: [String] = Array(CommandLine.arguments.dropFirst())
) throws -> ValidationCoordinatorArguments {
    var rootPath: String?
    var analysisManifestPath: String?
    var toolPath: String?
    var stateDirectoryPath: String?
    var outputDirectoryPath: String?
    var seenOptions: Set<String> = []
    var index = 0

    func requireValue(for option: String) throws -> String {
        guard index + 1 < rawArguments.count else {
            throw ValidationCoordinatorArgumentError.missingValue(
                option: option
            )
        }
        let value = rawArguments[index + 1]
        guard !value.hasPrefix("-") else {
            throw ValidationCoordinatorArgumentError.missingValue(
                option: option
            )
        }
        return value
    }

    while index < rawArguments.count {
        let option = rawArguments[index]
        guard seenOptions.insert(option).inserted else {
            throw ValidationCoordinatorArgumentError.duplicateOption(option)
        }

        switch option {
        case "--root":
            rootPath = try requireValue(for: option)
        case "--analysis-manifest":
            analysisManifestPath = try requireValue(for: option)
        case "--tool":
            toolPath = try requireValue(for: option)
        case "--state-dir":
            stateDirectoryPath = try requireValue(for: option)
        case "--output-dir":
            outputDirectoryPath = try requireValue(for: option)
        default:
            throw ValidationCoordinatorArgumentError.unknownOption(option)
        }
        index += 2
    }

    if rootPath != nil, analysisManifestPath != nil {
        throw ValidationCoordinatorArgumentError.conflictingWorkspaceInputs
    }
    guard let outputDirectoryPath else {
        throw ValidationCoordinatorArgumentError.missingRequiredArguments
    }

    let input: ValidationCoordinatorInput
    if let rootPath {
        input = .rootPath(rootPath)
    } else if let analysisManifestPath {
        guard toolPath == nil else {
            throw ValidationCoordinatorArgumentError
                .externalToolUnsupportedForManifest
        }
        input = .analysisManifestPath(analysisManifestPath)
    } else {
        throw ValidationCoordinatorArgumentError.missingRequiredArguments
    }

    return ValidationCoordinatorArguments(
        input: input,
        toolPath: toolPath,
        stateDirectoryPath: stateDirectoryPath,
        outputDirectoryPath: outputDirectoryPath
    )
}
