
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

    // MARK: - Initialization
    init(config: AppConfig, feature: FeatureBindingsContainer? = nil, featureOverrides: ((inout FeatureBindingsContainer.Overrides) -> Void)? = nil) {
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
        self._storage_config = config
        self._override_sub_feature = feature
        self._override_sub_apply_feature = featureOverrides
        let _subBuildCell_feature = _InnoDIDeferredCell<FeatureBindingsContainer>()
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
    static func withOverrides<OperationResult>(config: AppConfig, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> OperationResult) -> OperationResult {
        let container = Self(config: config, applyOverrides)
        return operation(container)
    }

    // MARK: - withOverrides (throws)
    static func withOverrides<OperationResult>(config: AppConfig, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> OperationResult) throws -> OperationResult {
        let container = Self(config: config, applyOverrides)
        return try operation(container)
    }

    // MARK: - withOverrides (async)
    static func withOverrides<OperationResult>(config: AppConfig, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async -> OperationResult) async -> OperationResult {
        let container = Self(config: config, applyOverrides)
        return await operation(container)
    }

    // MARK: - withOverrides (async throws)
    static func withOverrides<OperationResult>(config: AppConfig, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async throws -> OperationResult) async throws -> OperationResult {
        let container = Self(config: config, applyOverrides)
        return try await operation(container)
    }
}