
struct AppContainer {
    var config: AppConfig {
        get {
            return _storage_config
        }
    }

    private let _storage_config: AppConfig
    var feature: FeatureBindingsContainer {
        get {
            return _innoDISubBuild_feature()
        }
    }

    private let _override_sub_feature: FeatureBindingsContainer?

    private let _override_sub_apply_feature: ((inout FeatureBindingsContainer.Overrides) -> Void)?

    private let _innoDISubBuild_feature: @Sendable () -> FeatureBindingsContainer

    init(config: AppConfig, feature: FeatureBindingsContainer? = nil, featureOverrides: ((inout FeatureBindingsContainer.Overrides) -> Void)? = nil) {
        self._storage_config = config
        self._override_sub_feature = feature
        self._override_sub_apply_feature = featureOverrides
        let _subBuildCell_feature = _LazyCell<FeatureBindingsContainer>()
        self._innoDISubBuild_feature = {
            _subBuildCell_feature.resolve()
        }
        let _lazySelfForSub = self
        _subBuildCell_feature.bindResolver { () -> FeatureBindingsContainer in
            if let direct = _lazySelfForSub._override_sub_feature {
                return direct
            }
            if let apply = _lazySelfForSub._override_sub_apply_feature {
                return FeatureBindingsContainer(featureConfig: _lazySelfForSub.config, apply)
            }
            return FeatureBindingsContainer(featureConfig: _lazySelfForSub.config)
        }
    }

    struct Overrides {
        var feature: FeatureBindingsContainer? = nil
        var featureOverrides: ((inout FeatureBindingsContainer.Overrides) -> Void)? = nil
    }

    init(config: AppConfig, _ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(config: config, feature: overrides.feature, featureOverrides: overrides.featureOverrides)
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