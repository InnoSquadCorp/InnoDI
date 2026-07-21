
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var a: A
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var b: B
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var c: C

    // MARK: - Initialization
    init(a: A? = nil, b: B? = nil, c: C? = nil) {
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
        let _innoDILazyCell_c = _InnoDIDeferredCell<C>()
        self._storage_a = a ?? { (c: Lazy<C>) in
                A(c: c)
            }(.init {
                _innoDILazyCell_c.resolve()
            })
        self._storage_b = b ?? { (a: A) in
                B(a: a)
            }(self._storage_a!)
        self._storage_c = c ?? { (b: B) in
                C(b: b)
            }(self._storage_b!)
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
    init(_ _innoDIApplyOverrides: (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(a: _innoDIOverrides.a, b: _innoDIOverrides.b, c: _innoDIOverrides.c)
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