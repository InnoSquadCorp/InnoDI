
public struct AppContainer {
    @_Concurrency.MainActor @InnoDI._InnoDIProvideAccessor(recovery: false) public var config: AppConfig
    @_Concurrency.MainActor @InnoDI._InnoDISubContainerAccessor(recovery: false)
    public var feature: FeatureContainer

    // MARK: - Initialization
    @_Concurrency.MainActor public init(config: AppConfig, feature: FeatureContainer? = nil, featureOverrides: (@_Concurrency.MainActor (inout FeatureContainer._InnoDIMountOverrides) -> Void)? = nil) {
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
    @_Concurrency.MainActor public func featureRootView() -> FeatureRootScene {
        .init(container: feature)
    }

    #if canImport(InnoDISwiftUI) && canImport(SwiftUI)
    @_Concurrency.MainActor
    public func featureRootView<Identity>(
        identity: Identity,
        close: @escaping InnoDISwiftUI.DIContainerHostOwner<Identity, FeatureContainer>.Close = { _ in
        }
    ) -> some SwiftUI.View where Identity: Swift.Hashable & Swift.Sendable {
        InnoDISwiftUI.DIContainerHost(
            identity: identity,
            factory: { _ in
                self.feature
            },
            close: close,
            content: { container, _ in
                FeatureRootScene(container: container)
            },
            loading: {
                SwiftUI.EmptyView()
            },
            failure: { _, _ in
                SwiftUI.EmptyView()
            }
        )
    }
    #endif

    // MARK: - Overrides Builder
    @_Concurrency.MainActor public struct Overrides {
        public var feature: FeatureContainer? = nil
        public var featureOverrides: (@_Concurrency.MainActor (inout FeatureContainer._InnoDIMountOverrides) -> Void)? = nil
    }

    public typealias _InnoDIMountOverrides = Overrides

    // MARK: - Convenience Init with Overrides
    @_Concurrency.MainActor public init(config: AppConfig, _ _innoDIApplyOverrides: @_Concurrency.MainActor (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(config: config, feature: _innoDIOverrides.feature, featureOverrides: _innoDIOverrides.featureOverrides)
    }

    // MARK: - withOverrides
    @_Concurrency.MainActor public static func withOverrides<OperationResult>(config: AppConfig, _ _innoDIApplyOverrides: @_Concurrency.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @_Concurrency.MainActor (Self) -> OperationResult) -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
        return _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (throws)
    @_Concurrency.MainActor public static func withOverrides<OperationResult>(config: AppConfig, _ _innoDIApplyOverrides: @_Concurrency.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @_Concurrency.MainActor (Self) throws -> OperationResult) throws -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
        return try _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async)
    @_Concurrency.MainActor public static func withOverrides<OperationResult>(config: AppConfig, _ _innoDIApplyOverrides: @_Concurrency.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @_Concurrency.MainActor (Self) async -> OperationResult) async -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
        return await _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async throws)
    @_Concurrency.MainActor public static func withOverrides<OperationResult>(config: AppConfig, _ _innoDIApplyOverrides: @_Concurrency.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @_Concurrency.MainActor (Self) async throws -> OperationResult) async throws -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
        return try await _innoDIOperation(_innoDIContainer)
    }
}