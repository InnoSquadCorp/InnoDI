import Foundation

public enum DoctorCLI {
    public static let usage = """
    Usage: InnoDI-Doctor --root <path> [--json] [--apply] [--verify]

      default    Read-only source/config diagnosis; no resolution or build
      --json     Emit schema-v1 structured output
      --apply    Apply only safe InnoDI migrations after full preflight
      --verify   Run swift build or Tuist generation after diagnosis/application
    """

    public static func run(arguments: [String]) -> Int32 {
        if arguments.contains("--help") || arguments.contains("-h") {
            print(usage)
            return 0
        }
        guard let rootIndex = arguments.firstIndex(of: "--root"),
              arguments.indices.contains(rootIndex + 1) else {
            fputs("Error: --root <path> is required\n\(usage)\n", stderr)
            return 64
        }
        let known = Set(["--root", "--json", "--apply", "--verify"])
        for (index, argument) in arguments.enumerated()
            where argument.hasPrefix("--") && !known.contains(argument) {
            if index != rootIndex + 1 {
                fputs("Error: unknown option \(argument)\n", stderr)
                return 64
            }
        }

        do {
            let report = try InnoDIDoctor().run(
                root: URL(fileURLWithPath: arguments[rootIndex + 1], isDirectory: true),
                apply: arguments.contains("--apply"),
                verify: arguments.contains("--verify")
            )
            if arguments.contains("--json") {
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
                print("Proposed: \(report.proposedChangePaths.count), applied: \(report.appliedChangePaths.count), second-pass: \(report.secondPassChangeCount)")
                print("Graph: \(report.graphVerification.status.rawValue)")
                print("Verification: \(report.verification.status.rawValue)")
            }
            return report.isHealthy ? 0 : 1
        } catch {
            fputs("Error: \(error)\n", stderr)
            return 2
        }
    }
}
