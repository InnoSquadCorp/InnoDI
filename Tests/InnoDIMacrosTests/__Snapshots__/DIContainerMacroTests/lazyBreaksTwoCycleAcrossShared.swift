
struct AppContainer {
    var a: CoordinatorA {
        get {
            return _storage_a
        }
    }

    private let _storage_a: CoordinatorA
    var b: CoordinatorB {
        get {
            return _storage_b
        }
    }

    private let _storage_b: CoordinatorB

    init(a: CoordinatorA? = nil, b: CoordinatorB? = nil) {
        let _lazyCell_b = _LazyCell<CoordinatorB>()
        self._storage_a = a ?? { (b: Lazy<CoordinatorB>) in
                CoordinatorA(b: b)
            }(Lazy {
                _lazyCell_b.resolve()
            })
        self._storage_b = b ?? { (a: CoordinatorA) in
                CoordinatorB(a: a)
            }(self._storage_a)
        _lazyCell_b.storeValue(self._storage_b)
    }

    struct Overrides {
        var a: CoordinatorA? = nil
        var b: CoordinatorB? = nil
    }

    init(_ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(a: overrides.a, b: overrides.b)
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
