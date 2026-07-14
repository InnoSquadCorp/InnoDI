
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var baseURL: String

    // MARK: - Initialization
    init(baseURL: String) {
        self._storage_baseURL = baseURL
    }

    // MARK: - Overrides Builder
    struct Overrides {
    }

    // MARK: - Convenience Init with Overrides
    init(baseURL: String, _ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(baseURL: baseURL)
    }

    // MARK: - withOverrides
    static func withOverrides<OperationResult>(baseURL: String, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> OperationResult) -> OperationResult {
        let container = Self(baseURL: baseURL, applyOverrides)
        return operation(container)
    }

    // MARK: - withOverrides (throws)
    static func withOverrides<OperationResult>(baseURL: String, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> OperationResult) throws -> OperationResult {
        let container = Self(baseURL: baseURL, applyOverrides)
        return try operation(container)
    }

    // MARK: - withOverrides (async)
    nonisolated(nonsending) static func withOverrides<OperationResult>(baseURL: String, _ applyOverrides: (inout Overrides) -> Void, operation: nonisolated(nonsending) (Self) async -> OperationResult) async -> OperationResult {
        let container = Self(baseURL: baseURL, applyOverrides)
        return await operation(container)
    }

    // MARK: - withOverrides (async throws)
    nonisolated(nonsending) static func withOverrides<OperationResult>(baseURL: String, _ applyOverrides: (inout Overrides) -> Void, operation: nonisolated(nonsending) (Self) async throws -> OperationResult) async throws -> OperationResult {
        let container = Self(baseURL: baseURL, applyOverrides)
        return try await operation(container)
    }
}