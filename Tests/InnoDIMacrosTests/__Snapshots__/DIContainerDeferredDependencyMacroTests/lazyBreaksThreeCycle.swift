
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var a: A
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var b: B
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var c: C

    // MARK: - Initialization
    init(a: A? = nil, b: B? = nil, c: C? = nil, _innoDITrace: DITraceContext = .disabled) {
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
        self._innoDITraceOwner_a = _innoDITraceOwner
        self._innoDITraceOwner_b = _innoDITraceOwner
        self._innoDITraceOwner_c = _innoDITraceOwner
        let _innoDILazyCell_c = _InnoDIDeferredCell<C>()
        if let _innoDIOverride = a {
            self._storage_a = _innoDITraceOwner.overridden(
                member: "a",
                value: _innoDIOverride
            )
        } else {
            let _innoDITraceSpan_a = _innoDITraceOwner.start(
                member: "a"
            )
            let _innoDIResolved_a = { (c: Lazy<C>) in
                A(c: c)
            }(.init {
                    _innoDILazyCell_c.resolve()
                })
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
            let _innoDIResolved_b = { (a: A) in
                B(a: a)
            }(self._storage_a!)
            _innoDITraceOwner.finish(.success, span: _innoDITraceSpan_b)
            self._storage_b = _innoDIResolved_b
        }
        if let _innoDIOverride = c {
            self._storage_c = _innoDITraceOwner.overridden(
                member: "c",
                value: _innoDIOverride
            )
        } else {
            let _innoDITraceSpan_c = _innoDITraceOwner.start(
                member: "c"
            )
            let _innoDIResolved_c = { (b: B) in
                C(b: b)
            }(self._storage_b!)
            _innoDITraceOwner.finish(.success, span: _innoDITraceSpan_c)
            self._storage_c = _innoDIResolved_c
        }
        _innoDILazyCell_c.storeValue(self._storage_c!)
    }

    // MARK: - Overrides Builder
    struct Overrides {
        var a: A? = nil
        var b: B? = nil
        var c: C? = nil
    }

    typealias _InnoDIMountOverrides = Overrides

    // MARK: - Convenience Init with Overrides
    init(_innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(a: _innoDIOverrides.a, b: _innoDIOverrides.b, c: _innoDIOverrides.c, _innoDITrace: _innoDITrace)
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