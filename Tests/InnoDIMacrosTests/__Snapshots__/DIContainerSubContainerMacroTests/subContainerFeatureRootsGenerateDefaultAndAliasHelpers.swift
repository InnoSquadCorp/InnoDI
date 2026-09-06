
public struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false) public var config: AppConfig
    @InnoDI._InnoDISubContainerAccessor(recovery: false)
    public var feature: FeatureContainer

    // MARK: - Initialization
    public init(config: AppConfig, feature: FeatureContainer? = nil, featureOverrides: ((inout FeatureContainer._InnoDIMountOverrides) -> Void)? = nil) {
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
        _innoDISubBuildCell_feature.bindResolver { () -> FeatureContainer in
            if let direct = feature {
                return direct
            }
            if let apply = featureOverrides {
                return .init(config: config, apply)
            }
            return .init(config: config)
        }
    }

    // MARK: - SwiftUI Feature Roots
    public func featureRootView() -> FeatureRootScene {
        .init(container: feature)
    }

    public func featureShellRootView() -> FeatureShellScene {
        .init(container: feature)
    }

    // MARK: - Overrides Builder
    public struct Overrides {
        public var feature: FeatureContainer? = nil
        public var featureOverrides: ((inout FeatureContainer._InnoDIMountOverrides) -> Void)? = nil
    }

    public typealias _InnoDIMountOverrides = Overrides

    // MARK: - Convenience Init with Overrides
    public init(config: AppConfig, _ _innoDIApplyOverrides: (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(config: config, feature: _innoDIOverrides.feature, featureOverrides: _innoDIOverrides.featureOverrides)
    }

    // MARK: - withOverrides
    public static func withOverrides<OperationResult>(config: AppConfig, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) -> OperationResult) -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
        return _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (throws)
    public static func withOverrides<OperationResult>(config: AppConfig, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) throws -> OperationResult) throws -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
        return try _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async)
    public nonisolated(nonsending) static func withOverrides<OperationResult>(config: AppConfig, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async -> OperationResult) async -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
        return await _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async throws)
    public nonisolated(nonsending) static func withOverrides<OperationResult>(config: AppConfig, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async throws -> OperationResult) async throws -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
        return try await _innoDIOperation(_innoDIContainer)
    }
}