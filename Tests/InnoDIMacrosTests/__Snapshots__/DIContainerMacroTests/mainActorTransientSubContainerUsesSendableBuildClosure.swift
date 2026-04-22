
struct AppContainer {
    var config: Config {
        get {
            return _storage_config
        }
    }

    private let _storage_config: Config
    var feature: FeatureContainer {
        @MainActor get {
            return _innoDISubBuild_feature()
        }
    }

    private let _override_sub_feature: FeatureContainer?

    private let _override_sub_apply_feature: ((inout FeatureContainer.Overrides) -> Void)?

    private let _innoDISubBuild_feature: @MainActor @Sendable () -> FeatureContainer

    @MainActor init(config: Config, feature: FeatureContainer? = nil, featureOverrides: ((inout FeatureContainer.Overrides) -> Void)? = nil) {
        self._storage_config = config
        self._override_sub_feature = feature
        self._override_sub_apply_feature = featureOverrides
        let _subBuildCell_feature = _LazyCell<FeatureContainer>()
        self._innoDISubBuild_feature = {
            _subBuildCell_feature.resolve()
        }
        let _lazySelfForSub = self
        _subBuildCell_feature.bindResolver { () -> FeatureContainer in
            if let direct = _lazySelfForSub._override_sub_feature {
                return direct
            }
            if let apply = _lazySelfForSub._override_sub_apply_feature {
                return FeatureContainer(config: _lazySelfForSub.config, apply)
            }
            return FeatureContainer(config: _lazySelfForSub.config)
        }
    }

    struct Overrides {
        var feature: FeatureContainer? = nil
        var featureOverrides: ((inout FeatureContainer.Overrides) -> Void)? = nil
    }

    @MainActor init(config: Config, _ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(config: config, feature: overrides.feature, featureOverrides: overrides.featureOverrides)
    }

    @MainActor static func withOverrides<T>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> T) -> T {
        let container = Self(config: config, applyOverrides)
        return operation(container)
    }

    @MainActor static func withOverrides<T>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> T) throws -> T {
        let container = Self(config: config, applyOverrides)
        return try operation(container)
    }

    @MainActor static func withOverrides<T>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async -> T) async -> T {
        let container = Self(config: config, applyOverrides)
        return await operation(container)
    }

    @MainActor static func withOverrides<T>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async throws -> T) async throws -> T {
        let container = Self(config: config, applyOverrides)
        return try await operation(container)
    }
}