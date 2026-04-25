
struct AppContainer {
    var config: AppConfig {
        get {
            return _storage_config
        }
    }

    private let _storage_config: AppConfig
    var logger: Logger {
        get {
            return _storage_logger
        }
    }

    private let _storage_logger: Logger
    var feature: EmptyFeatureContainer {
        get {
            return _storage_sub_feature
        }
    }

    private let _storage_sub_feature: EmptyFeatureContainer

    private let _override_sub_feature: EmptyFeatureContainer?

    private let _override_sub_apply_feature: ((inout EmptyFeatureContainer.Overrides) -> Void)?

    init(config: AppConfig, logger: Logger? = nil, feature: EmptyFeatureContainer? = nil, featureOverrides: ((inout EmptyFeatureContainer.Overrides) -> Void)? = nil) {
        self._storage_config = config
        self._storage_logger = logger ?? Logger()
        if let direct = feature {
            self._storage_sub_feature = direct
        } else if let apply = featureOverrides {
            self._storage_sub_feature = EmptyFeatureContainer(apply)
        } else {
            self._storage_sub_feature = EmptyFeatureContainer()
        }
        self._override_sub_feature = feature
        self._override_sub_apply_feature = featureOverrides
    }

    struct Overrides {
        var logger: Logger? = nil
        var feature: EmptyFeatureContainer? = nil
        var featureOverrides: ((inout EmptyFeatureContainer.Overrides) -> Void)? = nil
    }

    init(config: AppConfig, _ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(config: config, logger: overrides.logger, feature: overrides.feature, featureOverrides: overrides.featureOverrides)
    }

    static func withOverrides<T>(config: AppConfig, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> T) -> T {
        let container = Self(config: config, applyOverrides)
        return operation(container)
    }

    static func withOverrides<T>(config: AppConfig, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> T) throws -> T {
        let container = Self(config: config, applyOverrides)
        return try operation(container)
    }

    static func withOverrides<T>(config: AppConfig, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async -> T) async -> T {
        let container = Self(config: config, applyOverrides)
        return await operation(container)
    }

    static func withOverrides<T>(config: AppConfig, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async throws -> T) async throws -> T {
        let container = Self(config: config, applyOverrides)
        return try await operation(container)
    }
}