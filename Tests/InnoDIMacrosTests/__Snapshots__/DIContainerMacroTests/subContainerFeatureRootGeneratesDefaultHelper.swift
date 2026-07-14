
public struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false) public var config: AppConfig

    private var _storage_config: AppConfig? = nil
    public var feature: FeatureContainer {
        get {
            return _storage_sub_feature
        }
    }

    private let _storage_sub_feature: FeatureContainer

    private let _override_sub_feature: FeatureContainer?

    private let _override_sub_apply_feature: ((inout FeatureContainer.Overrides) -> Void)?

    // MARK: - Initialization
    public init(config: AppConfig, feature: FeatureContainer? = nil, featureOverrides: ((inout FeatureContainer.Overrides) -> Void)? = nil) {
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
    public func featureRootView() -> FeatureRootScene {
        FeatureRootScene(container: feature)
    }

    // MARK: - Overrides Builder
    public struct Overrides {
        public var feature: FeatureContainer? = nil
        public var featureOverrides: ((inout FeatureContainer.Overrides) -> Void)? = nil
    }

    // MARK: - Convenience Init with Overrides
    public init(config: AppConfig, _ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(config: config, feature: overrides.feature, featureOverrides: overrides.featureOverrides)
    }

    // MARK: - withOverrides
    public static func withOverrides<OperationResult>(config: AppConfig, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> OperationResult) -> OperationResult {
        let container = Self(config: config, applyOverrides)
        return operation(container)
    }

    // MARK: - withOverrides (throws)
    public static func withOverrides<OperationResult>(config: AppConfig, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> OperationResult) throws -> OperationResult {
        let container = Self(config: config, applyOverrides)
        return try operation(container)
    }

    // MARK: - withOverrides (async)
    public nonisolated(nonsending) static func withOverrides<OperationResult>(config: AppConfig, _ applyOverrides: (inout Overrides) -> Void, operation: nonisolated(nonsending) (Self) async -> OperationResult) async -> OperationResult {
        let container = Self(config: config, applyOverrides)
        return await operation(container)
    }

    // MARK: - withOverrides (async throws)
    public nonisolated(nonsending) static func withOverrides<OperationResult>(config: AppConfig, _ applyOverrides: (inout Overrides) -> Void, operation: nonisolated(nonsending) (Self) async throws -> OperationResult) async throws -> OperationResult {
        let container = Self(config: config, applyOverrides)
        return try await operation(container)
    }
}