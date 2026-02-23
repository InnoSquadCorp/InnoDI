import Foundation

enum OutputFormat: Equatable {
    case mermaid
    case dot
    case ascii

    init?(string: String) {
        switch string.lowercased() {
        case "mermaid": self = .mermaid
        case "dot": self = .dot
        case "ascii": self = .ascii
        default: return nil
        }
    }
}

func parseArguments() -> (root: String, format: OutputFormat?, output: String?, validateDAG: Bool) {
    var root = FileManager.default.currentDirectoryPath
    var format: OutputFormat?
    var output: String?
    var validateDAG = false

    let args = Array(CommandLine.arguments.dropFirst())
    var index = 0

    func requireOptionValue(_ option: String, at index: Int) -> String {
        guard index + 1 < args.count else {
            fputs("Error: Option \(option) requires a value\n", stderr)
            printUsage()
            exit(1)
        }

        let value = args[index + 1]
        guard !value.hasPrefix("-") else {
            fputs("Error: Option \(option) requires a value\n", stderr)
            printUsage()
            exit(1)
        }

        return value
    }

    while index < args.count {
        let arg = args[index]

        if arg == "--root" {
            root = requireOptionValue(arg, at: index)
            index += 2
            continue
        } else if arg == "--format" {
            let value = requireOptionValue(arg, at: index)
            guard let outputFormat = OutputFormat(string: value) else {
                fputs("Error: Invalid --format value '\(value)'\n", stderr)
                printUsage()
                exit(1)
            }
            format = outputFormat
            index += 2
            continue
        } else if arg == "--output" {
            output = requireOptionValue(arg, at: index)
            index += 2
            continue
        } else if arg == "--validate-dag" {
            validateDAG = true
            index += 1
            continue
        } else if arg == "--help" || arg == "-h" {
            printUsage()
            exit(0)
        } else if arg.hasPrefix("-") {
            fputs("Warning: unrecognized option '\(arg)'\n", stderr)
        }

        index += 1
    }

    return (root, format, output, validateDAG)
}

func printUsage() {
    print("Usage: InnoDI-DependencyGraph --root <path> [--format <mermaid|dot|ascii>] [--output <file>] [--validate-dag]")
    print("")
    print("Options:")
    print("  --root <path>    Root directory of the project (default: current directory)")
    print("  --format <fmt>   Output format: mermaid (default), dot, ascii")
    print("  --output <file>  Output file path (default: stdout)")
    print("  --validate-dag   Validate dependency graph DAG and fail on cycles/ambiguity")
    print("  --help, -h       Show this help message")
}
