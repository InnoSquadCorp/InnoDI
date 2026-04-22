
struct AppContainer {
    var config: AppConfig {
        get {
            return _storage_config
        }
    }

    private let _storage_config: AppConfig
    var apiService: any APIClientProtocol {
        get {
            return _storage_apiService
        }
    }

    private let _storage_apiService: any APIClientProtocol
    var logger: Logger {
        get {
            return _storage_logger
        }
    }

    private let _storage_logger: Logger
    var feature: FeatureBindingsContainer {
        get {
            return _storage_sub_feature
        }
    }

    private let _storage_sub_feature: FeatureBindingsContainer

    private let _override_sub_feature: FeatureBindingsContainer?

    private let _override_sub_apply_feature: ((inout FeatureBindingsContainer.Overrides) -> Void)?

    init(config: AppConfig, apiService: any APIClientProtocol, logger: Logger? = nil, feature: FeatureBindingsContainer? = nil, featureOverrides: ((inout FeatureBindingsContainer.Overrides) -> Void)? = nil) {
        self._storage_config = config
        self._storage_apiService = apiService
        self._storage_logger = logger ?? Logger()
        if let direct = feature {
            self._storage_sub_feature = direct
         } else if let apply = featureOverrides {
            self._storage_sub_feature = FeatureBindingsContainer(featureConfig: self._storage_config, apiClient: self._storage_apiService, featureLogger: self._storage_logger, apply)
         } else {
            self._storage_sub_feature = FeatureBindingsContainer(featureConfig: self._storage_config, apiClient: self._storage_apiService, featureLogger: self._storage_logger)
        }
        self._override_sub_feature = feature
        self._override_sub_apply_feature = featureOverrides
    }

    struct Overrides {
        var logger: Logger? = nil
        var feature: FeatureBindingsContainer? = nil
        var featureOverrides: ((inout FeatureBindingsContainer.Overrides) -> Void)? = nil
    }

    init(config: AppConfig, apiService: any APIClientProtocol, _ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(config: config, apiService: apiService, logger: overrides.logger, feature: overrides.feature, featureOverrides: overrides.featureOverrides)
    }

    static func withOverrides<T>(config: AppConfig, apiService: any APIClientProtocol, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> T) -> T {
        let container = Self(config: config, apiService: apiService, applyOverrides)
        return operation(container)
    }

    static func withOverrides<T>(config: AppConfig, apiService: any APIClientProtocol, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> T) throws -> T {
        let container = Self(config: config, apiService: apiService, applyOverrides)
        return try operation(container)
    }

    static func withOverrides<T>(config: AppConfig, apiService: any APIClientProtocol, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async -> T) async -> T {
        let container = Self(config: config, apiService: apiService, applyOverrides)
        return await operation(container)
    }

    static func withOverrides<T>(config: AppConfig, apiService: any APIClientProtocol, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async throws -> T) async throws -> T {
        let container = Self(config: config, apiService: apiService, applyOverrides)
        return try await operation(container)
    }
}
