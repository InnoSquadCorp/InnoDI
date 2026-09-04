import Foundation
import InnoDIDependencyGraphCore

enum OutputFormat: Equatable {
    case mermaid
    case dot
    case ascii
    case json

    init?(string: String) {
        switch string.lowercased() {
        case "mermaid": self = .mermaid
        case "dot": self = .dot
        case "ascii": self = .ascii
        case "json": self = .json
        default: return nil
        }
    }
}

enum GraphInput: Equatable {
    case root(String)
    case analysisManifest(String)
}

enum GraphQuery: Equatable {
    case why(String)
    case dependents(String)
    case unused
}

struct GraphDiffInput: Equatable {
    let beforePath: String
    let afterPath: String
}

struct ParsedArguments: Equatable {
    var input: GraphInput?
    var rootPruning: DependencyGraphRootPruning?
    var format: OutputFormat?
    var output: String?
    var validateDAG: Bool
    var query: GraphQuery?
    var diffInput: GraphDiffInput?
    var checkGraphContract: Bool
    /// When non-nil, the CLI runs the `--diagnose-lock` maintenance command.
    /// An empty string asks the caller to use `<root>/.build`.
    var diagnoseLockPath: String?
    /// When non-nil, the CLI runs the `--cache-stats` maintenance command.
    /// An empty string asks the caller to use the default state directory.
    var cacheStatsPath: String?

    var rootPath: String? {
        guard case .root(let path) = input else {
            return nil
        }
        return path
    }
}

/// Outcome of parsing command-line arguments. `.helpRequested` is a normal
/// exit path the caller handles without an error code.
enum ArgumentParseResult: Equatable {
    case parsed(ParsedArguments, warnings: [String] = [])
    case helpRequested
    case failed(ArgumentsError)
}

enum ArgumentsError: Error, Equatable {
    case missingOptionValue(option: String)
    case invalidFormat(value: String)
    case invalidRootPruning(value: String)
    case unknownOption(option: String)
    case unexpectedArgument(value: String)
    case duplicateOption(option: String)
    case mutuallyExclusiveOptions(first: String, second: String)
    case missingGraphInput
    case missingRootPruning
    case rootPruningWithValidation
    case formatWithValidation
    case jsonRequiresAnalysisManifest
    case incompatibleMaintenanceOption(option: String)
    case incompatibleQueryOption(option: String)
    case incompatibleDiffOption(option: String)
    case diffRequiresTwoPaths
    case contractCheckRequiresDiff
}

/// Pure-function argument parser. No process exit, no stderr writes — the
/// caller decides how to surface errors and whether to print usage.
func parseArguments(
    _ rawArguments: [String] = Array(CommandLine.arguments.dropFirst())
) -> ArgumentParseResult {
    var rootPath: String?
    var manifestPath: String?
    var rootPruning: DependencyGraphRootPruning?
    var format: OutputFormat?
    var output: String?
    var validateDAG = false
    var query: GraphQuery?
    var queryOptionName: String?
    var diffInput: GraphDiffInput?
    var checkGraphContract = false
    var diagnoseLockPath: String?
    var cacheStatsPath: String?
    var seenOptions: Set<String> = []

    let args = rawArguments
    var index = 0

    func requireOptionValue(
        _ option: String,
        at index: Int
    ) -> Result<String, ArgumentsError> {
        guard index + 1 < args.count else {
            return .failure(.missingOptionValue(option: option))
        }

        let value = args[index + 1]
        guard !value.hasPrefix("-")
            || (option == "--output" && value == "-") else {
            return .failure(.missingOptionValue(option: option))
        }

        return .success(value)
    }

    func recordOption(_ option: String) -> ArgumentsError? {
        guard seenOptions.insert(option).inserted else {
            return .duplicateOption(option: option)
        }
        return nil
    }

    while index < args.count {
        let option = args[index]

        if option == "--help" || option == "-h" {
            return .helpRequested
        }

        if option == "--root"
            || option == "--analysis-manifest"
            || option == "--root-pruning"
            || option == "--format"
            || option == "--output"
            || option == "--why"
            || option == "--dependents" {
            if let error = recordOption(option) {
                return .failed(error)
            }
            let value: String
            switch requireOptionValue(option, at: index) {
            case .success(let parsedValue):
                value = parsedValue
            case .failure(let error):
                return .failed(error)
            }

            switch option {
            case "--root":
                rootPath = value
            case "--analysis-manifest":
                manifestPath = value
            case "--root-pruning":
                guard let parsed = DependencyGraphRootPruning(
                    rawValue: value.lowercased()
                ) else {
                    return .failed(.invalidRootPruning(value: value))
                }
                rootPruning = parsed
            case "--format":
                guard let parsed = OutputFormat(string: value) else {
                    return .failed(.invalidFormat(value: value))
                }
                format = parsed
            case "--output":
                output = value
            case "--why", "--dependents":
                if let queryOptionName {
                    return .failed(
                        .mutuallyExclusiveOptions(
                            first: queryOptionName,
                            second: option
                        )
                    )
                }
                queryOptionName = option
                query = option == "--why" ? .why(value) : .dependents(value)
            default:
                break
            }
            index += 2
            continue
        }

        if option == "--unused" {
            if let error = recordOption(option) {
                return .failed(error)
            }
            if let queryOptionName {
                return .failed(
                    .mutuallyExclusiveOptions(
                        first: queryOptionName,
                        second: option
                    )
                )
            }
            queryOptionName = option
            query = .unused
            index += 1
            continue
        }

        if option == "--check-contract" {
            if let error = recordOption(option) {
                return .failed(error)
            }
            checkGraphContract = true
            index += 1
            continue
        }

        if option == "--diff" {
            if let error = recordOption(option) {
                return .failed(error)
            }
            if let queryOptionName {
                return .failed(
                    .mutuallyExclusiveOptions(
                        first: queryOptionName,
                        second: option
                    )
                )
            }
            guard index + 2 < args.count,
                  !args[index + 1].hasPrefix("-"),
                  !args[index + 2].hasPrefix("-") else {
                return .failed(.diffRequiresTwoPaths)
            }
            queryOptionName = option
            diffInput = GraphDiffInput(
                beforePath: args[index + 1],
                afterPath: args[index + 2]
            )
            index += 3
            continue
        }

        if option == "--validate-dag" {
            if let error = recordOption(option) {
                return .failed(error)
            }
            validateDAG = true
            index += 1
            continue
        }

        if option == "--diagnose-lock" || option == "--cache-stats" {
            if let error = recordOption(option) {
                return .failed(error)
            }
            let path: String
            if index + 1 < args.count, !args[index + 1].hasPrefix("-") {
                path = args[index + 1]
                index += 2
            } else {
                path = ""
                index += 1
            }
            if option == "--diagnose-lock" {
                diagnoseLockPath = path
            } else {
                cacheStatsPath = path
            }
            continue
        }

        if option.hasPrefix("-") {
            return .failed(.unknownOption(option: option))
        }
        return .failed(.unexpectedArgument(value: option))
    }

    if rootPath != nil, manifestPath != nil {
        return .failed(
            .mutuallyExclusiveOptions(
                first: "--root",
                second: "--analysis-manifest"
            )
        )
    }
    if diagnoseLockPath != nil, cacheStatsPath != nil {
        return .failed(
            .mutuallyExclusiveOptions(
                first: "--diagnose-lock",
                second: "--cache-stats"
            )
        )
    }

    let input: GraphInput?
    if let rootPath {
        input = .root(rootPath)
    } else if let manifestPath {
        input = .analysisManifest(manifestPath)
    } else {
        input = nil
    }

    let isMaintenanceCommand = diagnoseLockPath != nil
        || cacheStatsPath != nil
    if checkGraphContract, diffInput == nil {
        return .failed(.contractCheckRequiresDiff)
    }
    if isMaintenanceCommand {
        if manifestPath != nil {
            return .failed(
                .incompatibleMaintenanceOption(
                    option: "--analysis-manifest"
                )
            )
        }
        for (isPresent, option) in [
            (rootPruning != nil, "--root-pruning"),
            (format != nil, "--format"),
            (output != nil, "--output"),
            (validateDAG, "--validate-dag"),
            (queryOptionName != nil, queryOptionName ?? "--query"),
        ] where isPresent {
            return .failed(.incompatibleMaintenanceOption(option: option))
        }
        return .parsed(
            ParsedArguments(
                input: input,
                rootPruning: nil,
                format: nil,
                output: nil,
                validateDAG: false,
                query: nil,
                diffInput: nil,
                checkGraphContract: false,
                diagnoseLockPath: diagnoseLockPath,
                cacheStatsPath: cacheStatsPath
            )
        )
    }

    if let diffInput {
        for (isPresent, option) in [
            (rootPath != nil, "--root"),
            (manifestPath != nil, "--analysis-manifest"),
            (rootPruning != nil, "--root-pruning"),
            (format != nil, "--format"),
            (validateDAG, "--validate-dag"),
        ] where isPresent {
            return .failed(.incompatibleDiffOption(option: option))
        }
        return .parsed(
            ParsedArguments(
                input: nil,
                rootPruning: nil,
                format: nil,
                output: output,
                validateDAG: false,
                query: nil,
                diffInput: diffInput,
                checkGraphContract: checkGraphContract,
                diagnoseLockPath: nil,
                cacheStatsPath: nil
            )
        )
    }

    guard let input else {
        return .failed(.missingGraphInput)
    }
    if query != nil {
        for (isPresent, option) in [
            (rootPruning != nil, "--root-pruning"),
            (format != nil, "--format"),
            (validateDAG, "--validate-dag"),
        ] where isPresent {
            return .failed(.incompatibleQueryOption(option: option))
        }
        return .parsed(
            ParsedArguments(
                input: input,
                rootPruning: nil,
                format: nil,
                output: output,
                validateDAG: false,
                query: query,
                diffInput: nil,
                checkGraphContract: false,
                diagnoseLockPath: nil,
                cacheStatsPath: nil
            )
        )
    }
    if validateDAG {
        if rootPruning != nil {
            return .failed(.rootPruningWithValidation)
        }
        if format != nil {
            return .failed(.formatWithValidation)
        }
    } else if rootPruning == nil {
        return .failed(.missingRootPruning)
    }
    if format == .json, case .root = input {
        return .failed(.jsonRequiresAnalysisManifest)
    }

    return .parsed(
        ParsedArguments(
            input: input,
            rootPruning: rootPruning,
            format: format,
            output: output,
            validateDAG: validateDAG,
            query: nil,
            diffInput: nil,
            checkGraphContract: false,
            diagnoseLockPath: nil,
            cacheStatsPath: nil
        )
    )
}

func usageText() -> String {
    """
    Usage: InnoDI-DependencyGraph (--root <path> | --analysis-manifest <path>) --root-pruning <all|roots> [--format <mermaid|dot|ascii|json>] [--output <file>]
           InnoDI-DependencyGraph (--root <path> | --analysis-manifest <path>) --validate-dag [--output <file>]
           InnoDI-DependencyGraph (--root <path> | --analysis-manifest <path>) (--why <container> | --dependents <container> | --unused) [--output <file>]
           InnoDI-DependencyGraph --diff <before.json> <after.json> [--check-contract] [--output <file>]
           InnoDI-DependencyGraph [--root <path>] --diagnose-lock [<scratch-path>]
           InnoDI-DependencyGraph [--root <path>] --cache-stats [<state-path>]

    Options:
      --root <path>              Legacy workspace-root input for text graphs or DAG validation
      --analysis-manifest <path> Target-scoped SwiftPM analysis manifest input
      --root-pruning <mode>      Required render scope: all or roots
      --format <fmt>             Output format: mermaid (default), dot, ascii, json
                                 JSON schema v3 requires --analysis-manifest
      --output <file>            Output file path (default: stdout; use - for stdout)
      --validate-dag             Validate the full selected target scope; cannot be pruned
      --why <container>          Show a shortest root-to-container inclusion path
      --dependents <container>   List direct and transitive dependents
      --unused                   List containers unreachable from every explicit root
      --diff <before> <after>    Compare two graph JSON v3 documents
      --check-contract           With --diff, exit 5 when any graph contract changed
      --diagnose-lock [path]     Inspect validation lock state (default: <root>/.build)
      --cache-stats [path]       Aggregate validation cache metrics
      --help, -h                 Show this help message
    """
}

func printUsage() {
    print(usageText())
}

extension ArgumentsError {
    var message: String {
        switch self {
        case .missingOptionValue(let option):
            return "Error: Option \(option) requires a value"
        case .invalidFormat(let value):
            return "Error: Invalid --format value '\(value)'"
        case .invalidRootPruning(let value):
            return "Error: Invalid --root-pruning value '\(value)'"
        case .unknownOption(let option):
            return "Error: Unknown option '\(option)'"
        case .unexpectedArgument(let value):
            return "Error: Unexpected argument '\(value)'"
        case .duplicateOption(let option):
            return "Error: Option \(option) may be specified only once"
        case .mutuallyExclusiveOptions(let first, let second):
            return "Error: Options \(first) and \(second) are mutually exclusive"
        case .missingGraphInput:
            return "Error: Exactly one of --root <path> or --analysis-manifest <path> is required"
        case .missingRootPruning:
            return "Error: Render mode requires --root-pruning <all|roots>"
        case .rootPruningWithValidation:
            return "Error: --root-pruning is not supported with --validate-dag"
        case .formatWithValidation:
            return "Error: --format is not supported with --validate-dag"
        case .jsonRequiresAnalysisManifest:
            return "Error: JSON schema v3 requires --analysis-manifest <path>"
        case .incompatibleMaintenanceOption(let option):
            return "Error: Option \(option) is not supported with maintenance commands"
        case .incompatibleQueryOption(let option):
            return "Error: Option \(option) is not supported with graph query commands"
        case .incompatibleDiffOption(let option):
            return "Error: Option \(option) is not supported with --diff"
        case .diffRequiresTwoPaths:
            return "Error: --diff requires <before.json> and <after.json>"
        case .contractCheckRequiresDiff:
            return "Error: --check-contract requires --diff <before.json> <after.json>"
        }
    }
}
