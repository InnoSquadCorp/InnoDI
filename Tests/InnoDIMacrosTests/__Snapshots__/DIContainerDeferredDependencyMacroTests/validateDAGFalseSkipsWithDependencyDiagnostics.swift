
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var service: Service
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var laterService: LaterService

    // MARK: - Initialization
    init(service: Service? = nil, laterService: LaterService? = nil) {
        self._storage_service = service ?? Service(laterService: laterService ?? InnoDI._innoDITrap("InnoDI could not resolve dependency 'laterService' while expanding a container with validateDAG: false. Supply an explicit override or complete the container wiring."), missingService: InnoDI._innoDITrap("InnoDI could not resolve dependency 'missingService' while expanding a container with validateDAG: false. Supply an explicit override or complete the container wiring."))
        self._storage_laterService = laterService ?? LaterService()
    }

    // MARK: - Overrides Builder
    struct Overrides {
        var service: Service? = nil
        var laterService: LaterService? = nil
    }

    typealias _InnoDIMountOverrides = Overrides

    // MARK: - Convenience Init with Overrides
    init(_ _innoDIApplyOverrides: (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(service: _innoDIOverrides.service, laterService: _innoDIOverrides.laterService)
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