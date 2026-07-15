
struct AppContainer {
    @Swift.MainActor @InnoDI._InnoDIProvideAccessor(recovery: false)
    var service: Service

    // MARK: - Initialization
    @Swift.MainActor init(service: Service? = nil) {
        self._override_service = service
    }

    // MARK: - Overrides Builder
    @Swift.MainActor struct Overrides {
        var service: Service? = nil
    }

    typealias _InnoDIMountOverrides = Overrides

    // MARK: - Convenience Init with Overrides
    @Swift.MainActor init(_ _innoDIApplyOverrides: @Swift.MainActor (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(service: _innoDIOverrides.service)
    }

    // MARK: - withOverrides
    @Swift.MainActor static func withOverrides<OperationResult>(_ _innoDIApplyOverrides: @Swift.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @Swift.MainActor (Self) -> OperationResult) -> OperationResult {
        let _innoDIContainer = Self(_innoDIApplyOverrides)
        return _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (throws)
    @Swift.MainActor static func withOverrides<OperationResult>(_ _innoDIApplyOverrides: @Swift.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @Swift.MainActor (Self) throws -> OperationResult) throws -> OperationResult {
        let _innoDIContainer = Self(_innoDIApplyOverrides)
        return try _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async)
    @Swift.MainActor static func withOverrides<OperationResult>(_ _innoDIApplyOverrides: @Swift.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @Swift.MainActor (Self) async -> OperationResult) async -> OperationResult {
        let _innoDIContainer = Self(_innoDIApplyOverrides)
        return await _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async throws)
    @Swift.MainActor static func withOverrides<OperationResult>(_ _innoDIApplyOverrides: @Swift.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @Swift.MainActor (Self) async throws -> OperationResult) async throws -> OperationResult {
        let _innoDIContainer = Self(_innoDIApplyOverrides)
        return try await _innoDIOperation(_innoDIContainer)
    }
}