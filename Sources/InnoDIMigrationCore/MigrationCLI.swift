import Foundation

public enum MigrationCLI {
    public static let usage = """
    Usage:
      InnoDI-Migrate --root <path> --check
      InnoDI-Migrate --root <path> --write

    Options:
      --root <path>  Swift package or source-tree root (required)
      --check        Exit nonzero when migration is required
      --write        Apply all safe migrations after a full-tree preflight
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
            let plan = try InnoDIMigrator().run(
                root: URL(fileURLWithPath: options.rootPath, isDirectory: true),
                mode: options.mode
            )
            for diagnostic in plan.diagnostics {
                fputs("\(diagnostic.rendered)\n", stderr)
            }
            guard plan.diagnostics.isEmpty else { return 2 }

            switch options.mode {
            case .check:
                if plan.requiresChanges {
                    for change in plan.changes {
                        print("MIGRATE \(change.path) [migrate.source-update]")
                    }
                    print("Migration required in \(plan.changes.count) file(s).")
                    return 1
                }
                print("InnoDI migration check passed (\(plan.scannedFileCount) Swift file(s)).")
                return 0
            case .write:
                for change in plan.changes {
                    print("MIGRATED \(change.path) [migrate.source-update]")
                }
                print("Migrated \(plan.changes.count) file(s).")
                return 0
            }
        } catch {
            fputs("Error: \(error)\n", stderr)
            return 2
        }
    }
}
