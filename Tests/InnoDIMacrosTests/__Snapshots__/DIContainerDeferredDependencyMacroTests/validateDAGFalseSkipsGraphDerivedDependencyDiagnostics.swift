
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var service: Service
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var laterService: LaterService

    // MARK: - Initialization
    init(service: Service? = nil, laterService: LaterService? = nil, _innoDITrace: DITraceContext = .disabled) {
        let _innoDITraceOwner = _InnoDITraceOwner(
            context: _innoDITrace,
            containerType: Self.self
        )
        self._innoDITraceOwner_service = _innoDITraceOwner
        self._innoDITraceOwner_laterService = _innoDITraceOwner
        if let _innoDIOverride = service {
            self._storage_service = _innoDITraceOwner.overridden(
                member: "service",
                value: _innoDIOverride
            )
        } else {
            let _innoDITraceSpan_service = _innoDITraceOwner.start(
                member: "service"
            )
            let _innoDIResolved_service = { (laterService: LaterService, missing: MissingService) in
                Service(laterService: laterService, missing: missing)
            }(laterService ?? InnoDI._innoDITrap("InnoDI could not resolve dependency 'laterService' while expanding a container with validateDAG: false. Supply an explicit override or complete the container wiring."), InnoDI._innoDITrap("InnoDI could not resolve dependency 'missing' while expanding a container with validateDAG: false. Supply an explicit override or complete the container wiring."))
            _innoDITraceOwner.finish(.success, span: _innoDITraceSpan_service)
            self._storage_service = _innoDIResolved_service
        }
        if let _innoDIOverride = laterService {
            self._storage_laterService = _innoDITraceOwner.overridden(
                member: "laterService",
                value: _innoDIOverride
            )
        } else {
            let _innoDITraceSpan_laterService = _innoDITraceOwner.start(
                member: "laterService"
            )
            let _innoDIResolved_laterService = LaterService()
            _innoDITraceOwner.finish(.success, span: _innoDITraceSpan_laterService)
            self._storage_laterService = _innoDIResolved_laterService
        }
    }

    // MARK: - Overrides Builder
    struct Overrides {
        var service: Service? = nil
        var laterService: LaterService? = nil
    }

    typealias _InnoDIMountOverrides = Overrides

    // MARK: - Convenience Init with Overrides
    init(_innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(service: _innoDIOverrides.service, laterService: _innoDIOverrides.laterService, _innoDITrace: _innoDITrace)
    }

    // MARK: - withOverrides
    static func withOverrides<OperationResult>(_innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) -> OperationResult) -> OperationResult {
        let _innoDIContainer = Self(_innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (throws)
    static func withOverrides<OperationResult>(_innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) throws -> OperationResult) throws -> OperationResult {
        let _innoDIContainer = Self(_innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return try _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async)
    nonisolated(nonsending) static func withOverrides<OperationResult>(_innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async -> OperationResult) async -> OperationResult {
        let _innoDIContainer = Self(_innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return await _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async throws)
    nonisolated(nonsending) static func withOverrides<OperationResult>(_innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async throws -> OperationResult) async throws -> OperationResult {
        let _innoDIContainer = Self(_innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return try await _innoDIOperation(_innoDIContainer)
    }
}