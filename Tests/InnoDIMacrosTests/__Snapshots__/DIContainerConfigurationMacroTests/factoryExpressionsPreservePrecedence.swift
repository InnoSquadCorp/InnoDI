
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var required: Service
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var selected: Service
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var optional: Service?

    // MARK: - Initialization
    init(required: Service? = nil, selected: Service? = nil, optional: Service?? = nil, _innoDITrace: DITraceContext = .disabled) {
        let _innoDITraceOwner = _InnoDITraceOwner(
            context: _innoDITrace,
            containerType: Self.self
        )
        self._innoDITraceOwner_required = _innoDITraceOwner
        self._innoDITraceOwner_selected = _innoDITraceOwner
        self._innoDITraceOwner_optional = _innoDITraceOwner
        if let _innoDIOverride = required {
            self._storage_required = _innoDITraceOwner.overridden(
                member: "required",
                value: _innoDIOverride
            )
        } else {
            let _innoDITraceSpan_required = _innoDITraceOwner.start(
                member: "required"
            )
            let _innoDIResolved_required = (try! makeRequiredService())
            _innoDITraceOwner.finish(.success, span: _innoDITraceSpan_required)
            self._storage_required = _innoDIResolved_required
        }
        if let _innoDIOverride = selected {
            self._storage_selected = _innoDITraceOwner.overridden(
                member: "selected",
                value: _innoDIOverride
            )
        } else {
            let _innoDITraceSpan_selected = _innoDITraceOwner.start(
                member: "selected"
            )
            let _innoDIResolved_selected = (usePrimary ? primaryService() : fallbackService())
            _innoDITraceOwner.finish(.success, span: _innoDITraceSpan_selected)
            self._storage_selected = _innoDIResolved_selected
        }
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
    init(_innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(required: _innoDIOverrides.required, selected: _innoDIOverrides.selected, optional: _innoDIOverrides.optional, _innoDITrace: _innoDITrace)
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