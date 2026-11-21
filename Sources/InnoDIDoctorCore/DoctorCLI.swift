import Foundation
import InnoDIMigrationCore

public enum DoctorCLI {
    public static let usage = """
    Usage: InnoDI-Doctor --root <path> [--json] [--apply] [--verify] [--scheme <name> --destination <specifier>] [--trust-module <name>]... [--swiftui-import-access <internal|package|public>]

      default    Read-only source/config diagnosis; no resolution or build
      --json     Emit schema-v3 structured output (including recovery paths)
      --apply    Apply only safe InnoDI migrations after full preflight
      --verify   Run swift build, or Tuist generation and compilation
      --scheme   Explicit Tuist-generated Xcode scheme required for compilation
      --destination  Explicit xcodebuild destination required for Tuist compilation
      --trust-module Treat an imported module as declaring no InnoDI-named
                 attribute or macro, as InnoDI-Migrate does; repeatable
      --swiftui-import-access  The SwiftUI import access choice given to
                 InnoDI-Migrate for this root; check and apply use it too
    """

    struct Options: Equatable {
        var rootPath: String
        var json = false
        var apply = false
        var verify = false
        var scheme: String?
        var destination: String?
        var trustedModules: Set<String> = []
        var swiftUIImportAccess: MigrationSwiftUIImportAccess?
    }

    enum ParseResult: Equatable {
        case options(Options)
        case help
        case failure(String)
    }

    /// Accepts each option once, except the repeatable `--trust-module`, and
    /// rejects unknown options and positional arguments, as `InnoDI-Migrate`
    /// does.
    static func parse(_ arguments: [String]) -> ParseResult {
        if arguments.contains("--help") || arguments.contains("-h") {
            return .help
        }
        var rootPath: String?
        var options = Options(rootPath: "")
        var seen: Set<String> = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            let isRepeatable = argument == "--trust-module"
            if !isRepeatable, seen.contains(argument) {
                return .failure("Option may be specified only once: \(argument)")
            }
            seen.insert(argument)
            switch argument {
            case "--json":
                options.json = true
            case "--apply":
                options.apply = true
            case "--verify":
                options.verify = true
            case "--root", "--scheme", "--destination", "--trust-module", "--swiftui-import-access":
                let valueIndex = index + 1
                guard arguments.indices.contains(valueIndex),
                      !arguments[valueIndex].isEmpty,
                      !arguments[valueIndex].hasPrefix("--") else {
                    return .failure("Missing value for option: \(argument)")
                }
                let value = arguments[valueIndex]
                switch argument {
                case "--root":
                    rootPath = value
                case "--scheme":
                    options.scheme = value
                case "--destination":
                    options.destination = value
                case "--trust-module":
                    options.trustedModules.insert(value)
                default:
                    guard let access = MigrationSwiftUIImportAccess(rawValue: value) else {
                        return .failure("Invalid SwiftUI import access '\(value)'; use internal, package, or public.")
                    }
                    options.swiftUIImportAccess = access
                }
                index += 1
            default:
                if argument.hasPrefix("-") {
                    return .failure("unknown option \(argument)")
                }
                return .failure("Unexpected positional argument: \(argument)")
            }
            index += 1
        }
        guard let rootPath else {
            return .failure("--root <path> is required")
        }
        options.rootPath = rootPath
        return .options(options)
    }

    public static func run(arguments: [String]) -> Int32 {
        let options: Options
        switch parse(arguments) {
        case .help:
            print(usage)
            return 0
        case .failure(let message):
            fputs("Error: \(message)\n\(usage)\n", stderr)
            return 64
        case .options(let parsed):
            options = parsed
        }

        do {
            let report = try InnoDIDoctor(
                trustedModules: options.trustedModules,
                swiftUIImportAccess: options.swiftUIImportAccess
            ).run(
                root: URL(fileURLWithPath: options.rootPath, isDirectory: true),
                apply: options.apply,
                verify: options.verify,
                tuistScheme: options.scheme,
                destination: options.destination
            )
            if options.json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                FileHandle.standardOutput.write(try encoder.encode(report))
                print()
            } else {
                print("InnoDI Doctor: \(report.mode)")
                print("Scanned: \(report.scannedSwiftFileCount) Swift file(s)")
                for item in report.diagnostics {
                    print("[\(item.severity.rawValue.uppercased())] \(item.id) \(item.path ?? "<workspace>"): \(item.message)")
                    print("  Recommendation: \(item.recommendation)")
                }
                // Like the InnoDI-Migrate report, proposed paths are listed
                // even when a migration diagnostic blocks every write.
                let blocked = !report.proposedChangePaths.isEmpty
                    && report.diagnostics.contains { $0.id.hasPrefix("migrate.") }
                print("Proposed: \(report.proposedChangePaths.count)\(blocked ? " (blocked; nothing can be applied until the migrate.* diagnostics are resolved)" : ""), applied: \(report.appliedChangePaths.count), second-pass: \(report.secondPassChangeCount)")
                for path in report.recoveryPaths {
                    print("RECOVERY \(path) [migrate.preserved-source]")
                }
                print("Graph: \(report.graphVerification.status.rawValue)")
                print("Verification: \(report.verification.status.rawValue)")
                print("  Generation: \(report.verification.generation.status.rawValue)")
                print("  Compilation: \(report.verification.compilation.status.rawValue)")
            }
            return report.isHealthy ? 0 : 1
        } catch {
            fputs("Error: \(error)\n", stderr)
            return 2
        }
    }
}
