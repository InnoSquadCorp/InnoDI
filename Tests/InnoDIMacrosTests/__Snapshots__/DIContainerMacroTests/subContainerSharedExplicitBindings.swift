
struct AppContainer {
    var config: AppConfig {
        get {
            return _storage_config
        }
    }

    private let _storage_config: AppConfig
    var feature: FeatureBindingsContainer {
        get {
            return _storage_sub_feature
        }
    }

    private let _storage_sub_feature: FeatureBindingsContainer

    private let _override_sub_feature: FeatureBindingsContainer?

    private let _override_sub_apply_feature: ((inout FeatureBindingsContainer.Overrides) -> Void)?

    // MARK: - Initialization
    init(config: AppConfig, feature: FeatureBindingsContainer? = nil, featureOverrides: ((inout FeatureBindingsContainer.Overrides) -> Void)? = nil) {
        self._storage_config = config
        if let direct = feature {
            self._storage_sub_feature = direct
        } else if let apply = featureOverrides {
            self._storage_sub_feature = FeatureBindingsContainer(featureConfig: self._storage_config, apply)
        } else {
            self._storage_sub_feature = FeatureBindingsContainer(featureConfig: self._storage_config)
        }
        self._override_sub_feature = feature
        self._override_sub_apply_feature = featureOverrides
    }

    // MARK: - Overrides Builder
    struct Overrides {
        var feature: FeatureBindingsContainer? = nil
        var featureOverrides: ((inout FeatureBindingsContainer.Overrides) -> Void)? = nil
    }

    // MARK: - Convenience Init with Overrides
    init(config: AppConfig, _ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(config: config, feature: overrides.feature, featureOverrides: overrides.featureOverrides)
    }

    // MARK: - withOverrides
    static func withOverrides<T>(config: AppConfig, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> T) -> T {
        let container = Self(config: config, applyOverrides)
        return operation(container)
    }

    // MARK: withOverrides (throws)
    static func withOverrides<T>(config: AppConfig, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> T) throws -> T {
        let container = Self(config: config, applyOverrides)
        return try operation(container)
    }

    // MARK: withOverrides (async)
    static func withOverrides<T>(config: AppConfig, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async -> T) async -> T {
        let container = Self(config: config, applyOverrides)
        return await operation(container)
    }

    // MARK: withOverrides (async throws)
    static func withOverrides<T>(config: AppConfig, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async throws -> T) async throws -> T {
        let container = Self(config: config, applyOverrides)
        return try await operation(container)
    }
}