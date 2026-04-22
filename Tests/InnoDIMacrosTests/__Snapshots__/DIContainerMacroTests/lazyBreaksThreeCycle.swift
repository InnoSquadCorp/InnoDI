
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

    init(a: A? = nil, b: B? = nil, c: C? = nil) {
        let _lazyCell_c = _LazyCell<C>()
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

    struct Overrides {
        var a: A? = nil
        var b: B? = nil
        var c: C? = nil
    }

    init(_ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(a: overrides.a, b: overrides.b, c: overrides.c)
    }

    static func withOverrides<T>(_ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> T) -> T {
        let container = Self(applyOverrides)
        return operation(container)
    }

    static func withOverrides<T>(_ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> T) throws -> T {
        let container = Self(applyOverrides)
        return try operation(container)
    }

    static func withOverrides<T>(_ applyOverrides: (inout Overrides) -> Void, operation: (Self) async -> T) async -> T {
        let container = Self(applyOverrides)
        return await operation(container)
    }

    static func withOverrides<T>(_ applyOverrides: (inout Overrides) -> Void, operation: (Self) async throws -> T) async throws -> T {
        let container = Self(applyOverrides)
        return try await operation(container)
    }
}