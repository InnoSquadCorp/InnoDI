
struct AppContainer {
    var a: A {
        get {
            return _storage_a
        }
    }

    private let _storage_a: A
    var b: B {
        get {
            return _storage_b
        }
    }

    private let _storage_b: B
    var c: C {
        get {
            return _storage_c
        }
    }

    private let _storage_c: C

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
            }(self._storage_a)
        self._storage_c = c ?? { (b: B) in
                C(b: b)
            }(self._storage_b)
        _lazyCell_c.storeValue(self._storage_c)
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
    static func withOverrides<T>(_ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> T) -> T {
        let container = Self(applyOverrides)
        return operation(container)
    }

    // MARK: withOverrides (throws)
    static func withOverrides<T>(_ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> T) throws -> T {
        let container = Self(applyOverrides)
        return try operation(container)
    }

    // MARK: withOverrides (async)
    static func withOverrides<T>(_ applyOverrides: (inout Overrides) -> Void, operation: (Self) async -> T) async -> T {
        let container = Self(applyOverrides)
        return await operation(container)
    }

    // MARK: withOverrides (async throws)
    static func withOverrides<T>(_ applyOverrides: (inout Overrides) -> Void, operation: (Self) async throws -> T) async throws -> T {
        let container = Self(applyOverrides)
        return try await operation(container)
    }
}