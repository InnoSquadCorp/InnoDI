
struct AppContainer {
    var config: AppConfig {
        get {
            return _storage_config
        }
    }

    private let _storage_config: AppConfig
    var apiClient: APIClient {
        get {
            return _storage_apiClient
        }
    }

    private let _storage_apiClient: APIClient
    var feature: FeatureContainer {
        get {
            return _storage_sub_feature
        }
    }

    private let _storage_sub_feature: FeatureContainer

    private let _override_sub_feature: FeatureContainer?

    private let _override_sub_apply_feature: ((inout FeatureContainer.Overrides) -> Void)?

    init(config: AppConfig, apiClient: APIClient, feature: FeatureContainer? = nil, featureOverrides: ((inout FeatureContainer.Overrides) -> Void)? = nil) {
        self._storage_config = config
        self._storage_apiClient = apiClient
        if let direct = feature {
            self._storage_sub_feature = direct
        } else if let apply = featureOverrides {
            self._storage_sub_feature = FeatureContainer(config: self._storage_config, apiClient: self._storage_apiClient, apply)
        } else {
            self._storage_sub_feature = FeatureContainer(config: self._storage_config, apiClient: self._storage_apiClient)
        }
        self._override_sub_feature = feature
        self._override_sub_apply_feature = featureOverrides
    }

    struct Overrides {
        var feature: FeatureContainer? = nil
        var featureOverrides: ((inout FeatureContainer.Overrides) -> Void)? = nil
    }

    init(config: AppConfig, apiClient: APIClient, _ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(config: config, apiClient: apiClient, feature: overrides.feature, featureOverrides: overrides.featureOverrides)
    }

    static func withOverrides<T>(config: AppConfig, apiClient: APIClient, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> T) -> T {
        let container = Self(config: config, apiClient: apiClient, applyOverrides)
        return operation(container)
    }

    static func withOverrides<T>(config: AppConfig, apiClient: APIClient, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> T) throws -> T {
        let container = Self(config: config, apiClient: apiClient, applyOverrides)
        return try operation(container)
    }

    static func withOverrides<T>(config: AppConfig, apiClient: APIClient, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async -> T) async -> T {
        let container = Self(config: config, apiClient: apiClient, applyOverrides)
        return await operation(container)
    }

    static func withOverrides<T>(config: AppConfig, apiClient: APIClient, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async throws -> T) async throws -> T {
        let container = Self(config: config, apiClient: apiClient, applyOverrides)
        return try await operation(container)
    }
}