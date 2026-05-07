
struct AppContainer {
    var serviceA: ServiceA {
        get {
            if let override = _override_serviceA {
                return override
            }
            return { (serviceB: ServiceB) in
                    ServiceA(serviceB: serviceB)
                }(self.serviceB)
        }
    }

    private let _override_serviceA: ServiceA?
    var serviceB: ServiceB {
        get {
            if let override = _override_serviceB {
                return override
            }
            return { (serviceA: ServiceA) in
                    ServiceB(serviceA: serviceA)
                }(self.serviceA)
        }
    }

    private let _override_serviceB: ServiceB?

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