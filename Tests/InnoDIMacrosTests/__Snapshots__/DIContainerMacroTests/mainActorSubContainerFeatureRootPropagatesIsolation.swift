
public struct AppContainer {
    @Swift.MainActor @InnoDI._InnoDIProvideAccessor(recovery: false) public var config: AppConfig
    @Swift.MainActor @InnoDI._InnoDISubContainerAccessor(recovery: false)
    public var feature: FeatureContainer

    // MARK: - Initialization
    @Swift.MainActor public init(config: AppConfig, feature: FeatureContainer? = nil, featureOverrides: (@Swift.MainActor (inout FeatureContainer._InnoDIMountOverrides) -> Void)? = nil) {
        self._storage_config = config
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

    // MARK: - SwiftUI Feature Roots
    @Swift.MainActor public func featureRootView() -> FeatureRootScene {
        .init(container: feature)
    }

    // MARK: - Overrides Builder
    @Swift.MainActor public struct Overrides {
        public var feature: FeatureContainer? = nil
        public var featureOverrides: (@Swift.MainActor (inout FeatureContainer._InnoDIMountOverrides) -> Void)? = nil
    }

    public typealias _InnoDIMountOverrides = Overrides

    // MARK: - Convenience Init with Overrides
    @Swift.MainActor public init(config: AppConfig, _ _innoDIApplyOverrides: @Swift.MainActor (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(config: config, feature: _innoDIOverrides.feature, featureOverrides: _innoDIOverrides.featureOverrides)
    }

    // MARK: - withOverrides
    @Swift.MainActor public static func withOverrides<OperationResult>(config: AppConfig, _ _innoDIApplyOverrides: @Swift.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @Swift.MainActor (Self) -> OperationResult) -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
        return _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (throws)
    @Swift.MainActor public static func withOverrides<OperationResult>(config: AppConfig, _ _innoDIApplyOverrides: @Swift.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @Swift.MainActor (Self) throws -> OperationResult) throws -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
        return try _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async)
    @Swift.MainActor public static func withOverrides<OperationResult>(config: AppConfig, _ _innoDIApplyOverrides: @Swift.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @Swift.MainActor (Self) async -> OperationResult) async -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
        return await _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async throws)
    @Swift.MainActor public static func withOverrides<OperationResult>(config: AppConfig, _ _innoDIApplyOverrides: @Swift.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @Swift.MainActor (Self) async throws -> OperationResult) async throws -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
        return try await _innoDIOperation(_innoDIContainer)
    }
}