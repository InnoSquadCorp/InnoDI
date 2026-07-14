
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var serviceA: ServiceA
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var serviceB: ServiceB

    // MARK: - Initialization
    init(serviceA: ServiceA? = nil, serviceB: ServiceB? = nil) {
        func _innoDIUnresolvedDependency<T>(_ name: String) -> T {
            fatalError("InnoDI could not resolve dependency '\(name)' while expanding a container with validateDAG: false. Supply an explicit override or complete the container wiring.")
        }
        self._override_serviceA = serviceA
        self._override_serviceB = serviceB
    }

    // MARK: - Overrides Builder
    struct Overrides {
        var serviceA: ServiceA? = nil
        var serviceB: ServiceB? = nil
    }

    // MARK: - Convenience Init with Overrides
    init(_ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(serviceA: overrides.serviceA, serviceB: overrides.serviceB)
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