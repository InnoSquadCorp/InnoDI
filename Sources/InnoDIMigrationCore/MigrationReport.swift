import Foundation

public enum MigrationReportStatus: String, Codable, Sendable, Equatable {
    case blocked
    case changesRequired
    case clean
}

public struct MigrationReportChange: Codable, Sendable, Equatable {
    public let code: String
    public let path: String

    public init(code: String, path: String) {
        self.code = code
        self.path = path
    }
}

public struct MigrationReportDiagnostic: Codable, Sendable, Equatable {
    public let code: String
    public let path: String
    public let message: String

    public init(code: String, path: String, message: String) {
        self.code = code
        self.path = path
        self.message = message
    }
}

public struct MigrationReport: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let status: MigrationReportStatus
    public let scannedFileCount: Int
    public let changeCount: Int
    public let diagnosticCount: Int
    public let requiresChanges: Bool
    public let canWrite: Bool
    public let changes: [MigrationReportChange]
    public let diagnostics: [MigrationReportDiagnostic]

    public init(plan: MigrationPlan) {
        schemaVersion = Self.currentSchemaVersion
        scannedFileCount = plan.scannedFileCount
        changeCount = plan.changes.count
        diagnosticCount = plan.diagnostics.count
        requiresChanges = plan.requiresChanges
        canWrite = plan.canWrite
        changes = plan.changes
            .map { MigrationReportChange(code: "migrate.source-update", path: $0.path) }
            .sorted { ($0.path, $0.code) < ($1.path, $1.code) }
        diagnostics = plan.diagnostics
            .map {
                MigrationReportDiagnostic(
                    code: $0.code,
                    path: $0.path,
                    message: $0.message
                )
            }
            .sorted { ($0.path, $0.code, $0.message) < ($1.path, $1.code, $1.message) }

        if !diagnostics.isEmpty {
            status = .blocked
        } else if requiresChanges {
            status = .changesRequired
        } else {
            status = .clean
        }
    }

    var exitCode: Int32 {
        switch status {
        case .clean:
            0
        case .changesRequired:
            1
        case .blocked:
            2
        }
    }

    func encodedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(self)
        data.append(0x0A)
        return data
    }
}
