
struct AppContainer {
    @MainActor
    var service: Service {
        get {
            if let override = _override_service {
                return override
            }
            return Service()
        }
    }

    private let _override_service: Service?

    // MARK: - Initialization
    @MainActor init(service: Service? = nil) {
        self._override_service = service
    }

    // MARK: - Overrides Builder
    @MainActor struct Overrides {
        var service: Service? = nil
    }

    // MARK: - Convenience Init with Overrides
    @MainActor init(_ applyOverrides: @MainActor (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(service: overrides.service)
    }

    // MARK: - withOverrides
    @MainActor static func withOverrides<OperationResult>(_ applyOverrides: @MainActor (inout Overrides) -> Void, operation: @MainActor (Self) -> OperationResult) -> OperationResult {
        let container = Self(applyOverrides)
        return operation(container)
    }

    // MARK: - withOverrides (throws)
    @MainActor static func withOverrides<OperationResult>(_ applyOverrides: @MainActor (inout Overrides) -> Void, operation: @MainActor (Self) throws -> OperationResult) throws -> OperationResult {
        let container = Self(applyOverrides)
        return try operation(container)
    }

    // MARK: - withOverrides (async)
    @MainActor static func withOverrides<OperationResult>(_ applyOverrides: @MainActor (inout Overrides) -> Void, operation: @MainActor (Self) async -> OperationResult) async -> OperationResult {
        let container = Self(applyOverrides)
        return await operation(container)
    }

    // MARK: - withOverrides (async throws)
    @MainActor static func withOverrides<OperationResult>(_ applyOverrides: @MainActor (inout Overrides) -> Void, operation: @MainActor (Self) async throws -> OperationResult) async throws -> OperationResult {
        let container = Self(applyOverrides)
        return try await operation(container)
    }
}