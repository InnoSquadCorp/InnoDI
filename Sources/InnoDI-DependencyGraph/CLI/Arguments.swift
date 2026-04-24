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
}

/// Outcome of parsing command-line arguments. `.helpRequested` is a normal
/// exit path the caller handles without an error code.
enum ArgumentParseResult: Equatable {
    case parsed(ParsedArguments)
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

    let args = rawArguments
    var index = 0

    func requireOptionValue(_ option: String, at index: Int) -> Result<String, ArgumentsError> {
        guard index + 1 < args.count else {
            return .failure(.missingOptionValue(option: option))
        }

        let value = args[index + 1]
        guard !value.hasPrefix("-") else {
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
        } else if arg == "--help" || arg == "-h" {
            return .helpRequested
        } else if arg.hasPrefix("-") {
            fputs("Warning: unrecognized option '\(arg)'\n", stderr)
        }

        index += 1
    }

    return .parsed(ParsedArguments(root: root, format: format, output: output, validateDAG: validateDAG))
}

func usageText() -> String {
    """
    Usage: InnoDI-DependencyGraph --root <path> [--format <mermaid|dot|ascii|json>] [--output <file>] [--validate-dag]

    Options:
      --root <path>    Root directory of the project (default: current directory)
      --format <fmt>   Output format: mermaid (default), dot, ascii, json
      --output <file>  Output file path (default: stdout)
      --validate-dag   Validate dependency graph DAG and fail on cycles/ambiguity
      --help, -h       Show this help message
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
