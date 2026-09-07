
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var holder: Holder
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var service: Service

    // MARK: - Initialization
    init(holder: Holder? = nil, service: Service? = nil, _innoDITrace: DITraceContext = .disabled) {
        final class _InnoDIDeferredCell<T>: @unchecked Swift.Sendable {
            private var value: T?
            private var resolver: (() -> T)?

            func storeValue(_ value: T) {
                self.value = value
            }

            func bindResolver(_ resolver: @escaping () -> T) {
                self.resolver = resolver
            }

            func resolve() -> T {
                guard let value else {
                    if let resolver {
                        return resolver()
                    }
                    return InnoDI._innoDITrap("InnoDI codegen invariant violated: deferred dependency resolved before initialization completed.")
                }
                return value
            }
        }
        let _innoDITraceOwner = _InnoDITraceOwner(
            context: _innoDITrace,
            containerType: Self.self
        )
        self._innoDITraceOwner_holder = _innoDITraceOwner
        self._innoDITraceOwner_service = _innoDITraceOwner
        let _innoDILazyCell_service = _InnoDIDeferredCell<Service>()
        if let _innoDIOverride = holder {
            self._storage_holder = _innoDITraceOwner.overridden(
                member: "holder",
                value: _innoDIOverride
            )
        } else {
            let _innoDITraceSpan_holder = _innoDITraceOwner.start(
                member: "holder"
            )
            let _innoDIResolved_holder = { (service: Lazy<Service>) in
                Holder(service: service)
            }(.init {
                    _innoDILazyCell_service.resolve()
                })
            _innoDITraceOwner.finish(.success, span: _innoDITraceSpan_holder)
            self._storage_holder = _innoDIResolved_holder
        }
        self._override_service = service
        _innoDILazyCell_service.bindResolver {
            service ?? {
                Service()
            }()
        }
    }

    // MARK: - Overrides Builder
    struct Overrides {
        var holder: Holder? = nil
        var service: Service? = nil
    }

    typealias _InnoDIMountOverrides = Overrides

    // MARK: - Convenience Init with Overrides
    init(_innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(holder: _innoDIOverrides.holder, service: _innoDIOverrides.service, _innoDITrace: _innoDITrace)
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