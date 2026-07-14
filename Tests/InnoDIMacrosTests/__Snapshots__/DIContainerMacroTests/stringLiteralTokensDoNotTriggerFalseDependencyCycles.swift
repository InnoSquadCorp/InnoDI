
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var a: ServiceA = ServiceA(name: "b")

    private var _storage_a: ServiceA? = nil
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var b: ServiceB = ServiceB(name: "a")

    private var _storage_b: ServiceB? = nil

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