import Foundation

public enum MigrationCLI {
    public static let usage = """
    Usage:
      InnoDI-Migrate --root <path> --check [--trust-module <name>]...
      InnoDI-Migrate --root <path> --report [--output <path>] [--trust-module <name>]...
      InnoDI-Migrate --root <path> --write [--trust-module <name>]...

    Options:
      --root <path>  Swift package or source-tree root (required)
      --check        Exit nonzero when migration is required
      --report       Emit a schema-v1 JSON migration report without source bodies
      --output <path>
                     Write the report atomically (default: stdout; use - for stdout)
      --write        Apply migrations and retain displaced files for recovery
      --trust-module <name>
                     Treat an imported module as declaring no InnoDI-named
                     attribute or macro (repeatable)
      --swiftui-import-access <internal|public>
                     Resolve ambiguous SwiftUI import access for this root;
                     use public where SwiftUI types appear in public API.
                     Exported imports always remain public.
      --help, -h     Show this help
    """

    @discardableResult
    public static func run(arguments: [String]) -> Int32 {
        let options: MigrationOptions
        switch parseMigrationArguments(arguments) {
        case .helpRequested:
            print(usage)
            return 0
        case .failure(let error):
            fputs("Error: \(error.description)\n", stderr)
            fputs("\(usage)\n", stderr)
            return 64
        case .options(let parsed):
            options = parsed
        }

        do {
            let plan = try InnoDIMigrator(
                trustedModules: Set(options.trustedModules),
                swiftUIImportAccess: options.swiftUIImportAccess
            ).run(
                root: URL(fileURLWithPath: options.rootPath, isDirectory: true),
                mode: options.mode
            )

            if options.mode == .report {
                let report = MigrationReport(plan: plan)
                try emit(report: report, outputPath: options.outputPath)
                return report.exitCode
            }

            for diagnostic in plan.diagnostics {
                fputs("\(diagnostic.rendered)\n", stderr)
            }
            guard plan.diagnostics.isEmpty else { return 2 }

            switch options.mode {
            case .check:
                if plan.requiresChanges {
                    for change in plan.changes {
                        print("MIGRATE \(change.path) [migrate.source-update]\(renderedRules(change.rules))")
                    }
                    print("Migration required in \(plan.changes.count) file(s).")
                    return 1
                }
                print("InnoDI migration check passed (\(plan.scannedFileCount) Swift file(s)).")
                return 0
            case .write:
                for change in plan.changes {
                    print("MIGRATED \(change.path) [migrate.source-update]\(renderedRules(change.rules))")
                }
                for path in plan.recoveryPaths {
                    print("RECOVERY \(path) [migrate.preserved-source]")
                }
                print("Migrated \(plan.changes.count) file(s).")
                return 0
            case .report:
                preconditionFailure("Report mode returns before text rendering.")
            }
        } catch {
            fputs("Error: \(error)\n", stderr)
            return 2
        }
    }

    private static func emit(
        report: MigrationReport,
        outputPath: String?
    ) throws {
        let data = try report.encodedJSON()
        guard let outputPath, outputPath != "-" else {
            FileHandle.standardOutput.write(data)
            return
        }

        do {
            try data.write(
                to: URL(fileURLWithPath: outputPath),
                options: .atomic
            )
        } catch {
            throw MigrationError.cannotWriteReport(
                path: outputPath,
                reason: error.localizedDescription
            )
        }
    }
}

/// Lists the rules behind one file change after its stable change code.
private func renderedRules(_ rules: [String]) -> String {
    rules.isEmpty ? "" : " rules: " + rules.joined(separator: ", ")
}
