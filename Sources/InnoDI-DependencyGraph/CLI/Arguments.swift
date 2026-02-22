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

func parseArguments() -> (root: String, format: OutputFormat?, output: String?) {
    var root = FileManager.default.currentDirectoryPath
    var format: OutputFormat?
    var output: String?

    var iterator = CommandLine.arguments.makeIterator()
    _ = iterator.next()

    while let arg = iterator.next() {
        if arg == "--root", let value = iterator.next() {
            root = value
        } else if arg == "--format", let value = iterator.next() {
            format = OutputFormat(string: value)
        } else if arg == "--output", let value = iterator.next() {
            output = value
        } else if arg == "--help" || arg == "-h" {
            printUsage()
            exit(0)
        } else if arg.hasPrefix("-") {
            fputs("Warning: unrecognized option '\(arg)'\n", stderr)
        }
    }

    return (root, format, output)
}

func printUsage() {
    print("Usage: InnoDI-DependencyGraph --root <path> [--format <mermaid|dot|ascii>] [--output <file>]")
    print("")
    print("Options:")
    print("  --root <path>    Root directory of the project (default: current directory)")
    print("  --format <fmt>   Output format: mermaid (default), dot, ascii")
    print("  --output <file>  Output file path (default: stdout)")
    print("  --help, -h       Show this help message")
}
