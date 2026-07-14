
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false) var config: AppConfig

    private var _storage_config: AppConfig? = nil
    @InnoDI._InnoDIProvideAccessor(recovery: false) var apiService: any APIClientProtocol

    private var _storage_apiService: (any APIClientProtocol)? = nil
    @InnoDI._InnoDIProvideAccessor(recovery: false) var logger: Logger

    private var _storage_logger: Logger? = nil
    var feature: FeatureBindingsContainer {
        get {
            return _storage_sub_feature
        }
    }

    private let _storage_sub_feature: FeatureBindingsContainer

    private let _override_sub_feature: FeatureBindingsContainer?

    private let _override_sub_apply_feature: ((inout FeatureBindingsContainer.Overrides) -> Void)?

    // MARK: - Initialization
    init(config: AppConfig, apiService: any APIClientProtocol, logger: Logger? = nil, feature: FeatureBindingsContainer? = nil, featureOverrides: ((inout FeatureBindingsContainer.Overrides) -> Void)? = nil) {
        self._storage_config = config
        self._storage_apiService = apiService
        self._storage_logger = logger ?? Logger()
        if let direct = feature {
            self._storage_sub_feature = direct
        } else if let apply = featureOverrides {
            self._storage_sub_feature = FeatureBindingsContainer(featureConfig: self._storage_config!, apiClient: self._storage_apiService!, featureLogger: self._storage_logger!, apply)
        } else {
            self._storage_sub_feature = FeatureBindingsContainer(featureConfig: self._storage_config!, apiClient: self._storage_apiService!, featureLogger: self._storage_logger!)
        }
        self._override_sub_feature = feature
        self._override_sub_apply_feature = featureOverrides
    }

    // MARK: - Overrides Builder
    struct Overrides {
        var logger: Logger? = nil
        var feature: FeatureBindingsContainer? = nil
        var featureOverrides: ((inout FeatureBindingsContainer.Overrides) -> Void)? = nil
    }

    // MARK: - Convenience Init with Overrides
    init(config: AppConfig, apiService: any APIClientProtocol, _ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(config: config, apiService: apiService, logger: overrides.logger, feature: overrides.feature, featureOverrides: overrides.featureOverrides)
    }

    // MARK: - withOverrides
    static func withOverrides<OperationResult>(config: AppConfig, apiService: any APIClientProtocol, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> OperationResult) -> OperationResult {
        let container = Self(config: config, apiService: apiService, applyOverrides)
        return operation(container)
    }

    // MARK: - withOverrides (throws)
    static func withOverrides<OperationResult>(config: AppConfig, apiService: any APIClientProtocol, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> OperationResult) throws -> OperationResult {
        let container = Self(config: config, apiService: apiService, applyOverrides)
        return try operation(container)
    }

    // MARK: - withOverrides (async)
    nonisolated(nonsending) static func withOverrides<OperationResult>(config: AppConfig, apiService: any APIClientProtocol, _ applyOverrides: (inout Overrides) -> Void, operation: nonisolated(nonsending) (Self) async -> OperationResult) async -> OperationResult {
        let container = Self(config: config, apiService: apiService, applyOverrides)
        return await operation(container)
    }

    // MARK: - withOverrides (async throws)
    nonisolated(nonsending) static func withOverrides<OperationResult>(config: AppConfig, apiService: any APIClientProtocol, _ applyOverrides: (inout Overrides) -> Void, operation: nonisolated(nonsending) (Self) async throws -> OperationResult) async throws -> OperationResult {
        let container = Self(config: config, apiService: apiService, applyOverrides)
        return try await operation(container)
    }
}