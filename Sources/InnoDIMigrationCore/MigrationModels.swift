public struct MigrationDiagnostic: Sendable, Equatable, Comparable {
    public let code: String
    public let path: String
    public let message: String

    public init(code: String, path: String, message: String) {
        self.code = code
        self.path = path
        self.message = message
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.path, lhs.code, lhs.message) < (rhs.path, rhs.code, rhs.message)
    }

    public var rendered: String {
        "[\(code)] \(path): \(message)"
    }
}

public struct MigrationFileChange: Sendable, Equatable {
    public let path: String
    public let originalSource: String
    public let migratedSource: String
    public let hadUTF8ByteOrderMark: Bool

    public init(
        path: String,
        originalSource: String,
        migratedSource: String,
        hadUTF8ByteOrderMark: Bool = false
    ) {
        self.path = path
        self.originalSource = originalSource
        self.migratedSource = migratedSource
        self.hadUTF8ByteOrderMark = hadUTF8ByteOrderMark
    }
}

public struct MigrationPlan: Sendable, Equatable {
    public let scannedFileCount: Int
    public let changes: [MigrationFileChange]
    public let diagnostics: [MigrationDiagnostic]

    public init(
        scannedFileCount: Int,
        changes: [MigrationFileChange],
        diagnostics: [MigrationDiagnostic]
    ) {
        self.scannedFileCount = scannedFileCount
        self.changes = changes
        self.diagnostics = diagnostics.sorted()
    }

    public var requiresChanges: Bool { !changes.isEmpty }
    public var canWrite: Bool { diagnostics.isEmpty }
}

public enum MigrationError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidRoot(String)
    case cannotEnumerateRoot(path: String, reason: String)
    case cannotRead(path: String, reason: String)
    case cannotWrite(path: String, reason: String)

    public var description: String {
        switch self {
        case .invalidRoot(let path):
            "Migration root is not a readable directory: \(path)"
        case .cannotEnumerateRoot(let path, let reason):
            "Could not enumerate migration root \(path): \(reason)"
        case .cannotRead(let path, let reason):
            "Could not read \(path): \(reason)"
        case .cannotWrite(let path, let reason):
            "Could not write \(path): \(reason)"
        }
    }
}
