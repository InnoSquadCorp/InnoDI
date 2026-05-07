
struct AppContainer {
    var a: ServiceA {
        get {
            return _storage_a
        }
    }

    private let _storage_a: ServiceA
    var b: ServiceB {
        get {
            return _storage_b
        }
    }

    private let _storage_b: ServiceB

    // MARK: - Initialization
    init(a: ServiceA? = nil, b: ServiceB? = nil) {
        self._storage_a = a ?? ServiceA(name: "b")
        self._storage_b = b ?? ServiceB(name: "a")
    }

    // MARK: - Overrides Builder
    struct Overrides {
        var a: ServiceA? = nil
        var b: ServiceB? = nil
    }

    // MARK: - Convenience Init with Overrides
    init(_ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(a: overrides.a, b: overrides.b)
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
    static func withOverrides<OperationResult>(_ applyOverrides: (inout Overrides) -> Void, operation: (Self) async -> OperationResult) async -> OperationResult {
        let container = Self(applyOverrides)
        return await operation(container)
    }

    // MARK: - withOverrides (async throws)
    static func withOverrides<OperationResult>(_ applyOverrides: (inout Overrides) -> Void, operation: (Self) async throws -> OperationResult) async throws -> OperationResult {
        let container = Self(applyOverrides)
        return try await operation(container)
    }
}