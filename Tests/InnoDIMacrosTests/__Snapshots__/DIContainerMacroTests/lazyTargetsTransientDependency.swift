
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

    // MARK: - Initialization
    init(holder: Holder? = nil, service: Service? = nil) {
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
        let _lazyCell_service = _InnoDIDeferredCell<Service>()
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

    // MARK: - Overrides Builder
    struct Overrides {
        var holder: Holder? = nil
        var service: Service? = nil
    }

    // MARK: - Convenience Init with Overrides
    init(_ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(holder: overrides.holder, service: overrides.service)
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