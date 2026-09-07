
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false) var config: AppConfig
    @InnoDI._InnoDIProvideAccessor(recovery: false) var logger: Logger
    @InnoDI._InnoDISubContainerAccessor(recovery: false)
    var feature: EmptyFeatureContainer

    // MARK: - Initialization
    init(config: AppConfig, logger: Logger? = nil, feature: EmptyFeatureContainer? = nil, featureOverrides: ((inout EmptyFeatureContainer._InnoDIMountOverrides) -> Void)? = nil, _innoDITrace: DITraceContext = .disabled) {
        let _innoDITraceOwner = _InnoDITraceOwner(
            context: _innoDITrace,
            containerType: Self.self
        )
        self._innoDITraceOwner_logger = _innoDITraceOwner
        self._storage_config = config
        if let _innoDIOverride = logger {
            self._storage_logger = _innoDITraceOwner.overridden(
                member: "logger",
                value: _innoDIOverride
            )
        } else {
            let _innoDITraceSpan_logger = _innoDITraceOwner.start(
                member: "logger"
            )
            let _innoDIResolved_logger = Logger()
            _innoDITraceOwner.finish(.success, span: _innoDITraceSpan_logger)
            self._storage_logger = _innoDIResolved_logger
        }
        if let direct = feature {
            self._storage_sub_feature = direct
        } else if let apply = featureOverrides {
            self._storage_sub_feature = .init(_innoDITrace: _innoDITrace, apply)
        } else {
            self._storage_sub_feature = .init(_innoDITrace: _innoDITrace)
        }
        self._override_sub_feature = feature
        self._override_sub_apply_feature = featureOverrides
    }

    // MARK: - Overrides Builder
    struct Overrides {
        var logger: Logger? = nil
        var feature: EmptyFeatureContainer? = nil
        var featureOverrides: ((inout EmptyFeatureContainer._InnoDIMountOverrides) -> Void)? = nil
    }

    typealias _InnoDIMountOverrides = Overrides

    // MARK: - Convenience Init with Overrides
    init(config: AppConfig, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(config: config, logger: _innoDIOverrides.logger, feature: _innoDIOverrides.feature, featureOverrides: _innoDIOverrides.featureOverrides, _innoDITrace: _innoDITrace)
    }

    // MARK: - withOverrides
    static func withOverrides<OperationResult>(config: AppConfig, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) -> OperationResult) -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (throws)
    static func withOverrides<OperationResult>(config: AppConfig, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) throws -> OperationResult) throws -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return try _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async)
    nonisolated(nonsending) static func withOverrides<OperationResult>(config: AppConfig, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async -> OperationResult) async -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return await _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async throws)
    nonisolated(nonsending) static func withOverrides<OperationResult>(config: AppConfig, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async throws -> OperationResult) async throws -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return try await _innoDIOperation(_innoDIContainer)
    }
}