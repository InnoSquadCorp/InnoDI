
public struct AppContainer {
    @MainActor @InnoDI._InnoDIProvideAccessor(recovery: false) public var config: AppConfig
    @MainActor
    public var feature: FeatureContainer {
        get {
            return _storage_sub_feature
        }
    }

    private let _storage_sub_feature: FeatureContainer

    private let _override_sub_feature: FeatureContainer?

    private let _override_sub_apply_feature: (@MainActor (inout FeatureContainer.Overrides) -> Void)?

    // MARK: - Initialization
    @MainActor public init(config: AppConfig, feature: FeatureContainer? = nil, featureOverrides: (@MainActor (inout FeatureContainer.Overrides) -> Void)? = nil) {
        self._storage_config = config
        if let direct = feature {
            self._storage_sub_feature = direct
        } else if let apply = featureOverrides {
            self._storage_sub_feature = FeatureContainer(config: self._storage_config!, apply)
        } else {
            self._storage_sub_feature = FeatureContainer(config: self._storage_config!)
        }
        self._override_sub_feature = feature
        self._override_sub_apply_feature = featureOverrides
    }

    // MARK: - SwiftUI Feature Roots
    @MainActor public func featureRootView() -> FeatureRootScene {
        FeatureRootScene(container: feature)
    }

    // MARK: - Overrides Builder
    @MainActor public struct Overrides {
        public var feature: FeatureContainer? = nil
        public var featureOverrides: (@MainActor (inout FeatureContainer.Overrides) -> Void)? = nil
    }

    // MARK: - Convenience Init with Overrides
    @MainActor public init(config: AppConfig, _ applyOverrides: @MainActor (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(config: config, feature: overrides.feature, featureOverrides: overrides.featureOverrides)
    }

    // MARK: - withOverrides
    @MainActor public static func withOverrides<OperationResult>(config: AppConfig, _ applyOverrides: @MainActor (inout Overrides) -> Void, operation: @MainActor (Self) -> OperationResult) -> OperationResult {
        let container = Self(config: config, applyOverrides)
        return operation(container)
    }

    // MARK: - withOverrides (throws)
    @MainActor public static func withOverrides<OperationResult>(config: AppConfig, _ applyOverrides: @MainActor (inout Overrides) -> Void, operation: @MainActor (Self) throws -> OperationResult) throws -> OperationResult {
        let container = Self(config: config, applyOverrides)
        return try operation(container)
    }

    // MARK: - withOverrides (async)
    @MainActor public static func withOverrides<OperationResult>(config: AppConfig, _ applyOverrides: @MainActor (inout Overrides) -> Void, operation: @MainActor (Self) async -> OperationResult) async -> OperationResult {
        let container = Self(config: config, applyOverrides)
        return await operation(container)
    }

    // MARK: - withOverrides (async throws)
    @MainActor public static func withOverrides<OperationResult>(config: AppConfig, _ applyOverrides: @MainActor (inout Overrides) -> Void, operation: @MainActor (Self) async throws -> OperationResult) async throws -> OperationResult {
        let container = Self(config: config, applyOverrides)
        return try await operation(container)
    }
}