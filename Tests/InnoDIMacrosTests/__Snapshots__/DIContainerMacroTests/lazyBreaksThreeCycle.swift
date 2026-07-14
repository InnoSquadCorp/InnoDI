
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var a: A

    private var _storage_a: A? = nil
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var b: B

    private var _storage_b: B? = nil
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var c: C

    private var _storage_c: C? = nil

    // MARK: - Initialization
    init(a: A? = nil, b: B? = nil, c: C? = nil) {
        final class _InnoDIDeferredCell<T>: @unchecked Sendable {
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
                    preconditionFailure("InnoDI codegen invariant violated: deferred dependency resolved before initialization completed.")
                }
                return value
            }
        }
        let _lazyCell_c = _InnoDIDeferredCell<C>()
        self._storage_a = a ?? { (c: Lazy<C>) in
                A(c: c)
            }(Lazy {
                _lazyCell_c.resolve()
            })
        self._storage_b = b ?? { (a: A) in
                B(a: a)
            }(self._storage_a!)
        self._storage_c = c ?? { (b: B) in
                C(b: b)
            }(self._storage_b!)
        _lazyCell_c.storeValue(self._storage_c!)
    }

    // MARK: - Overrides Builder
    struct Overrides {
        var a: A? = nil
        var b: B? = nil
        var c: C? = nil
    }

    // MARK: - Convenience Init with Overrides
    init(_ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(a: overrides.a, b: overrides.b, c: overrides.c)
    }

    // MARK: - withOverrides
    static func withOverrides<OperationResult>(_ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> OperationResult) -> OperationResult {
        let container = Self(applyOverrides)
        return operation(container)
    }

    // MARK: - withOverrides (throws)
    static func withOverrides<OperationResult>(_ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> OperationResult) throws -> OperationResult {
        let container = Self(applyOverrides)
        return try operation(container)
    }

    // MARK: - withOverrides (async)
    nonisolated(nonsending) static func withOverrides<OperationResult>(_ applyOverrides: (inout Overrides) -> Void, operation: nonisolated(nonsending) (Self) async -> OperationResult) async -> OperationResult {
        let container = Self(applyOverrides)
        return await operation(container)
    }

    // MARK: - withOverrides (async throws)
    nonisolated(nonsending) static func withOverrides<OperationResult>(_ applyOverrides: (inout Overrides) -> Void, operation: nonisolated(nonsending) (Self) async throws -> OperationResult) async throws -> OperationResult {
        let container = Self(applyOverrides)
        return try await operation(container)
    }
}