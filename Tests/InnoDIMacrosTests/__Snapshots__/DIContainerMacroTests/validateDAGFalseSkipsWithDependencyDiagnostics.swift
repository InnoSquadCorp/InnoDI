
struct AppContainer {
    var service: Service {
        get {
            return _storage_service
        }
    }

    private let _storage_service: Service
    var laterService: LaterService {
        get {
            return _storage_laterService
        }
    }

    private let _storage_laterService: LaterService

    // MARK: - Initialization
    init(service: Service? = nil, laterService: LaterService? = nil) {
        func _innoDIUnresolvedDependency<T>(_ name: String) -> T {
            fatalError("InnoDI could not resolve dependency '\(name)' while expanding a container with validateDAG: false. Supply an explicit override or complete the container wiring.")
        }
        self._storage_service = service ?? Service(laterService: laterService ?? _innoDIUnresolvedDependency("laterService"), missingService: _innoDIUnresolvedDependency("missingService"))
        self._storage_laterService = laterService ?? LaterService()
    }

    // MARK: - Overrides Builder
    struct Overrides {
        var service: Service? = nil
        var laterService: LaterService? = nil
    }

    // MARK: - Convenience Init with Overrides
    init(_ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(service: overrides.service, laterService: overrides.laterService)
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