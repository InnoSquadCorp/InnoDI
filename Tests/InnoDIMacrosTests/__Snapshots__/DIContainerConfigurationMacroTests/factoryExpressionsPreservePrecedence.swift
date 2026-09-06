
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var required: Service
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var selected: Service
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var optional: Service?

    // MARK: - Initialization
    init(required: Service? = nil, selected: Service? = nil, optional: Service?? = nil) {
        self._storage_required = required ?? (try! makeRequiredService())
        self._storage_selected = selected ?? (usePrimary ? primaryService() : fallbackService())
        self._override_optional = optional
    }

    // MARK: - Overrides Builder
    struct Overrides {
        var required: Service? = nil
        var selected: Service? = nil
        var optional: Service?? = nil
    }

    typealias _InnoDIMountOverrides = Overrides

    // MARK: - Convenience Init with Overrides
    init(_ _innoDIApplyOverrides: (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(required: _innoDIOverrides.required, selected: _innoDIOverrides.selected, optional: _innoDIOverrides.optional)
    }

    // MARK: - withOverrides
    static func withOverrides<OperationResult>(_ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) -> OperationResult) -> OperationResult {
        let _innoDIContainer = Self(_innoDIApplyOverrides)
        return _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (throws)
    static func withOverrides<OperationResult>(_ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) throws -> OperationResult) throws -> OperationResult {
        let _innoDIContainer = Self(_innoDIApplyOverrides)
        return try _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async)
    nonisolated(nonsending) static func withOverrides<OperationResult>(_ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async -> OperationResult) async -> OperationResult {
        let _innoDIContainer = Self(_innoDIApplyOverrides)
        return await _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async throws)
    nonisolated(nonsending) static func withOverrides<OperationResult>(_ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async throws -> OperationResult) async throws -> OperationResult {
        let _innoDIContainer = Self(_innoDIApplyOverrides)
        return try await _innoDIOperation(_innoDIContainer)
    }
}