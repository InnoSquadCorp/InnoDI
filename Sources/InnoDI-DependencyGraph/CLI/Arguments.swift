import Foundation

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

struct ParsedArguments: Equatable {
    var root: String
    var format: OutputFormat?
    var output: String?
    var validateDAG: Bool
    /// When non-nil, the CLI runs the `--diagnose-lock` subcommand
    /// against the resolved scratch path instead of rendering or
    /// validating a graph. The associated value is the directory the
    /// user passed (or the default).
    var diagnoseLockPath: String?
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
}

/// Pure-function argument parser. No process exit, no stderr writes — the
/// caller decides how to surface errors and whether to print usage.
func parseArguments(_ rawArguments: [String] = Array(CommandLine.arguments.dropFirst()))
    -> ArgumentParseResult
{
    var root = FileManager.default.currentDirectoryPath
    var format: OutputFormat?
    var output: String?
    var validateDAG = false
    var diagnoseLockPath: String?
    var warnings: [String] = []

    let args = rawArguments
    var index = 0

    func requireOptionValue(_ option: String, at index: Int) -> Result<String, ArgumentsError> {
        guard index + 1 < args.count else {
            return .failure(.missingOptionValue(option: option))
        }

        let value = args[index + 1]
        guard !value.hasPrefix("-") || (option == "--output" && value == "-") else {
            return .failure(.missingOptionValue(option: option))
        }

        return .success(value)
    }

    while index < args.count {
        let arg = args[index]

        if arg == "--root" {
            switch requireOptionValue(arg, at: index) {
            case .success(let value):
                root = value
                index += 2
                continue
            case .failure(let error):
                return .failed(error)
            }
        } else if arg == "--format" {
            switch requireOptionValue(arg, at: index) {
            case .success(let value):
                guard let outputFormat = OutputFormat(string: value) else {
                    return .failed(.invalidFormat(value: value))
                }
                format = outputFormat
                index += 2
                continue
            case .failure(let error):
                return .failed(error)
            }
        } else if arg == "--output" {
            switch requireOptionValue(arg, at: index) {
            case .success(let value):
                output = value
                index += 2
                continue
            case .failure(let error):
                return .failed(error)
            }
        } else if arg == "--validate-dag" {
            validateDAG = true
            index += 1
            continue
        } else if arg == "--diagnose-lock" {
            // `--diagnose-lock` accepts an optional path. Without it
            // the subcommand defaults to scanning `<root>/.build`,
            // which matches SPM's standard scratch directory.
            if index + 1 < args.count, !args[index + 1].hasPrefix("-") {
                diagnoseLockPath = args[index + 1]
                index += 2
            } else {
                diagnoseLockPath = ""  // sentinel: caller fills in default
                index += 1
            }
            continue
        } else if arg == "--help" || arg == "-h" {
            return .helpRequested
        } else if arg.hasPrefix("-") {
            warnings.append("Warning: unrecognized option '\(arg)'")
        }

        index += 1
    }

    return .parsed(
        ParsedArguments(
            root: root,
            format: format,
            output: output,
            validateDAG: validateDAG,
            diagnoseLockPath: diagnoseLockPath
        ),
        warnings: warnings
    )
}

func usageText() -> String {
    """
    Usage: InnoDI-DependencyGraph --root <path> [--format <mermaid|dot|ascii|json>] [--output <file>] [--validate-dag]
           InnoDI-DependencyGraph --diagnose-lock [<scratch-path>]

    Options:
      --root <path>          Root directory of the project (default: current directory)
      --format <fmt>         Output format: mermaid (default), dot, ascii, json
      --output <file>        Output file path (default: stdout; use - for stdout)
      --validate-dag         Validate dependency graph DAG and fail on cycles/ambiguity
      --diagnose-lock [path] Print the validation coordinator's view of the lock
                             directory: filesystem class, environment, and any
                             active or stale lock files with their metadata.
                             Defaults to <root>/.build when no path is given.
      --help, -h             Show this help message
    """
}

func printUsage() {
    print(usageText())
}

/// Describes the argument error in a stable format for stderr output.
extension ArgumentsError {
    var message: String {
        switch self {
        case .missingOptionValue(let option):
            return "Error: Option \(option) requires a value"
        case .invalidFormat(let value):
            return "Error: Invalid --format value '\(value)'"
        }
    }
}
