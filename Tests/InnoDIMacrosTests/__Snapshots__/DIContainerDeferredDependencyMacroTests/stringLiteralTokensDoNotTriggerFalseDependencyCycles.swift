
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var a: ServiceA = ServiceA(name: "b")
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var b: ServiceB = ServiceB(name: "a")

    // MARK: - Initialization
    init(a: ServiceA? = nil, b: ServiceB? = nil, _innoDITrace: DITraceContext = .disabled) {
        let _innoDITraceOwner = _InnoDITraceOwner(
            context: _innoDITrace,
            containerType: Self.self
        )
        self._innoDITraceOwner_a = _innoDITraceOwner
        self._innoDITraceOwner_b = _innoDITraceOwner
        if let _innoDIOverride = a {
            self._storage_a = _innoDITraceOwner.overridden(
                member: "a",
                value: _innoDIOverride
            )
        } else {
            let _innoDITraceSpan_a = _innoDITraceOwner.start(
                member: "a"
            )
            let _innoDIResolved_a = ServiceA(name: "b")
            _innoDITraceOwner.finish(.success, span: _innoDITraceSpan_a)
            self._storage_a = _innoDIResolved_a
        }
        if let _innoDIOverride = b {
            self._storage_b = _innoDITraceOwner.overridden(
                member: "b",
                value: _innoDIOverride
            )
        } else {
            let _innoDITraceSpan_b = _innoDITraceOwner.start(
                member: "b"
            )
            let _innoDIResolved_b = ServiceB(name: "a")
            _innoDITraceOwner.finish(.success, span: _innoDITraceSpan_b)
            self._storage_b = _innoDIResolved_b
        }
    }

    // MARK: - Overrides Builder
    struct Overrides {
        var a: ServiceA? = nil
        var b: ServiceB? = nil
    }

    typealias _InnoDIMountOverrides = Overrides

    // MARK: - Convenience Init with Overrides
    init(_innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(a: _innoDIOverrides.a, b: _innoDIOverrides.b, _innoDITrace: _innoDITrace)
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