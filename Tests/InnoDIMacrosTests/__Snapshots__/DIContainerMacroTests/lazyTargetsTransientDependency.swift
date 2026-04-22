
struct AppContainer {
    var holder: Holder {
        get {
            return _storage_holder
        }
    }

    private let _storage_holder: Holder
    var service: Service {
        get {
            if let override = _override_service {
                return override
            }
            return {
                Service()
            }()
        }
    }

    private let _override_service: Service?

    init(holder: Holder? = nil, service: Service? = nil) {
        let _lazyCell_service = _LazyCell<Service>()
        self._storage_holder = holder ?? { (service: Lazy<Service>) in
                Holder(service: service)
            }(Lazy {
                _lazyCell_service.resolve()
            })
        self._override_service = service
        let _lazySelf = self
        _lazyCell_service.bindResolver {
            _lazySelf.service
        }
    }

    struct Overrides {
        var holder: Holder? = nil
        var service: Service? = nil
    }

    init(_ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(holder: overrides.holder, service: overrides.service)
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