
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var serviceA: ServiceA
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var serviceB: ServiceB

    // MARK: - Initialization
    init(serviceA: ServiceA? = nil, serviceB: ServiceB? = nil) {
        self._override_serviceA = serviceA
        self._override_serviceB = serviceB
    }

    // MARK: - Overrides Builder
    struct Overrides {
        var serviceA: ServiceA? = nil
        var serviceB: ServiceB? = nil
    }

    typealias _InnoDIMountOverrides = Overrides

    // MARK: - Convenience Init with Overrides
    init(_ _innoDIApplyOverrides: (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(serviceA: _innoDIOverrides.serviceA, serviceB: _innoDIOverrides.serviceB)
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