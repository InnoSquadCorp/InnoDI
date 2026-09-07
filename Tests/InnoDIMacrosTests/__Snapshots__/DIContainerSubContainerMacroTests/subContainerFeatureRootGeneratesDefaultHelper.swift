
public struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false) public var config: AppConfig
    @InnoDI._InnoDISubContainerAccessor(recovery: false)
    public var feature: FeatureContainer

    // MARK: - Initialization
    public init(config: AppConfig, feature: FeatureContainer? = nil, featureOverrides: ((inout FeatureContainer._InnoDIMountOverrides) -> Void)? = nil, _innoDITrace: DITraceContext = .disabled) {
        self._storage_config = config
        if let direct = feature {
            self._storage_sub_feature = direct
        } else if let apply = featureOverrides {
            self._storage_sub_feature = .init(config: self._storage_config!, _innoDITrace: _innoDITrace, apply)
        } else {
            self._storage_sub_feature = .init(config: self._storage_config!, _innoDITrace: _innoDITrace)
        }
        self._override_sub_feature = feature
        self._override_sub_apply_feature = featureOverrides
    }

    // MARK: - SwiftUI Feature Roots
    public func featureRootView() -> FeatureRootScene {
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
    public struct Overrides {
        public var feature: FeatureContainer? = nil
        public var featureOverrides: ((inout FeatureContainer._InnoDIMountOverrides) -> Void)? = nil
    }

    public typealias _InnoDIMountOverrides = Overrides

    // MARK: - Convenience Init with Overrides
    public init(config: AppConfig, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(config: config, feature: _innoDIOverrides.feature, featureOverrides: _innoDIOverrides.featureOverrides, _innoDITrace: _innoDITrace)
    }

    // MARK: - withOverrides
    public static func withOverrides<OperationResult>(config: AppConfig, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) -> OperationResult) -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (throws)
    public static func withOverrides<OperationResult>(config: AppConfig, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) throws -> OperationResult) throws -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return try _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async)
    public nonisolated(nonsending) static func withOverrides<OperationResult>(config: AppConfig, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async -> OperationResult) async -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return await _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async throws)
    public nonisolated(nonsending) static func withOverrides<OperationResult>(config: AppConfig, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async throws -> OperationResult) async throws -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return try await _innoDIOperation(_innoDIContainer)
    }
}