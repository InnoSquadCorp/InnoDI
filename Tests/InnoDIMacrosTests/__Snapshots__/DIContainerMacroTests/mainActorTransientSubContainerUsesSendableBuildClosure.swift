
struct AppContainer {
    @Swift.MainActor @InnoDI._InnoDIProvideAccessor(recovery: false) var config: Config
    @Swift.MainActor @InnoDI._InnoDISubContainerAccessor(recovery: false)
    var feature: FeatureContainer

    // MARK: - Initialization
    @Swift.MainActor init(config: Config, feature: FeatureContainer? = nil, featureOverrides: (@Swift.MainActor (inout FeatureContainer._InnoDIMountOverrides) -> Void)? = nil) {
        final class _InnoDIDeferredCell<T>: @unchecked Swift.Sendable {
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
                    return InnoDI._innoDITrap("InnoDI codegen invariant violated: deferred dependency resolved before initialization completed.")
                }
                return value
            }
        }
        self._storage_config = config
        self._override_sub_feature = feature
        self._override_sub_apply_feature = featureOverrides
        let _innoDISubBuildCell_feature = _InnoDIDeferredCell<FeatureContainer>()
        self._innoDISubBuild_feature = {
            _innoDISubBuildCell_feature.resolve()
        }
        let _innoDILazySelfForSub = self
        _innoDISubBuildCell_feature.bindResolver { () -> FeatureContainer in
            if let direct = _innoDILazySelfForSub._override_sub_feature {
                return direct
            }
            if let apply = _innoDILazySelfForSub._override_sub_apply_feature {
                return .init(config: _innoDILazySelfForSub.config, apply)
            }
            return .init(config: _innoDILazySelfForSub.config)
        }
    }

    // MARK: - Overrides Builder
    @Swift.MainActor struct Overrides {
        var feature: FeatureContainer? = nil
        var featureOverrides: (@Swift.MainActor (inout FeatureContainer._InnoDIMountOverrides) -> Void)? = nil
    }

    typealias _InnoDIMountOverrides = Overrides

    // MARK: - Convenience Init with Overrides
    @Swift.MainActor init(config: Config, _ _innoDIApplyOverrides: @Swift.MainActor (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(config: config, feature: _innoDIOverrides.feature, featureOverrides: _innoDIOverrides.featureOverrides)
    }

    // MARK: - withOverrides
    @Swift.MainActor static func withOverrides<OperationResult>(config: Config, _ _innoDIApplyOverrides: @Swift.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @Swift.MainActor (Self) -> OperationResult) -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
        return _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (throws)
    @Swift.MainActor static func withOverrides<OperationResult>(config: Config, _ _innoDIApplyOverrides: @Swift.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @Swift.MainActor (Self) throws -> OperationResult) throws -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
        return try _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async)
    @Swift.MainActor static func withOverrides<OperationResult>(config: Config, _ _innoDIApplyOverrides: @Swift.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @Swift.MainActor (Self) async -> OperationResult) async -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
        return await _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async throws)
    @Swift.MainActor static func withOverrides<OperationResult>(config: Config, _ _innoDIApplyOverrides: @Swift.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @Swift.MainActor (Self) async throws -> OperationResult) async throws -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
        return try await _innoDIOperation(_innoDIContainer)
    }
}