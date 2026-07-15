
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false) var config: AppConfig
    @InnoDI._InnoDIProvideAccessor(recovery: false) var logger: Logger
    @InnoDI._InnoDISubContainerAccessor(recovery: false)
    var feature: FeatureContainer

    // MARK: - Initialization
    init(config: AppConfig, logger: Logger? = nil, feature: FeatureContainer? = nil, featureOverrides: ((inout FeatureContainer._InnoDIMountOverrides) -> Void)? = nil) {
        self._storage_config = config
        self._storage_logger = logger ?? Logger()
        if let direct = feature {
            self._storage_sub_feature = direct
        } else if let apply = featureOverrides {
            self._storage_sub_feature = .init(config: self._storage_config!, apply)
        } else {
            self._storage_sub_feature = .init(config: self._storage_config!)
        }
        self._override_sub_feature = feature
        self._override_sub_apply_feature = featureOverrides
    }

    // MARK: - Overrides Builder
    struct Overrides {
        var logger: Logger? = nil
        var feature: FeatureContainer? = nil
        var featureOverrides: ((inout FeatureContainer._InnoDIMountOverrides) -> Void)? = nil
    }

    typealias _InnoDIMountOverrides = Overrides

    // MARK: - Convenience Init with Overrides
    init(config: AppConfig, _ _innoDIApplyOverrides: (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(config: config, logger: _innoDIOverrides.logger, feature: _innoDIOverrides.feature, featureOverrides: _innoDIOverrides.featureOverrides)
    }

    // MARK: - withOverrides
    static func withOverrides<OperationResult>(config: AppConfig, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) -> OperationResult) -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
        return _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (throws)
    static func withOverrides<OperationResult>(config: AppConfig, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) throws -> OperationResult) throws -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
        return try _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async)
    nonisolated(nonsending) static func withOverrides<OperationResult>(config: AppConfig, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async -> OperationResult) async -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
        return await _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async throws)
    nonisolated(nonsending) static func withOverrides<OperationResult>(config: AppConfig, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async throws -> OperationResult) async throws -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
        return try await _innoDIOperation(_innoDIContainer)
    }
}