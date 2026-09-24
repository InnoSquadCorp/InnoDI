
struct AppContainer {
    @_Concurrency.MainActor @InnoDI._InnoDIProvideAccessor(recovery: false)
    var apiClient: APIClient

    // MARK: - Initialization
    @_Concurrency.MainActor init(apiClient: APIClient? = nil, _innoDITrace: DITraceContext = .disabled) {
        let _innoDITraceOwner = _InnoDITraceOwner(
            context: _innoDITrace,
            containerType: Self.self
        )
        self._innoDITraceOwner_apiClient = _innoDITraceOwner
        if let _innoDIOverride = apiClient {
            self._storage_apiClient = _innoDITraceOwner.overridden(
                member: "apiClient",
                value: _innoDIOverride
            )
        } else {
            let _innoDITraceSpan_apiClient = _innoDITraceOwner.start(
                member: "apiClient"
            )
            let _innoDIResolved_apiClient = APIClient()
            _innoDITraceOwner.finish(.success, span: _innoDITraceSpan_apiClient)
            self._storage_apiClient = _innoDIResolved_apiClient
        }
    }

    // MARK: - Overrides Builder
    @_Concurrency.MainActor struct Overrides: InnoDI.DIMainActorOverrideEffectValidating {
        var apiClient: APIClient? = nil
        static let requiredEffectOverrides: [InnoDI.DIProviderEffectRequirement] = [InnoDI.DIProviderEffectRequirement(providerName: "apiClient", effect: .sideEffect)]
        var missingEffectOverrides: [InnoDI.DIProviderEffectRequirement] {
            var missing: [InnoDI.DIProviderEffectRequirement] = []
                if self.apiClient == nil {
                    missing.append(
                        InnoDI.DIProviderEffectRequirement(
                            providerName: "apiClient",
                            effect: .sideEffect
                        )
                    )
                }
            return missing
        }
    }

    typealias _InnoDIMountOverrides = Overrides

    // MARK: - Convenience Init with Overrides
    @_Concurrency.MainActor init(_innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: @_Concurrency.MainActor (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(apiClient: _innoDIOverrides.apiClient, _innoDITrace: _innoDITrace)
    }

    // MARK: - withOverrides
    @_Concurrency.MainActor static func withOverrides<OperationResult>(_innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: @_Concurrency.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @_Concurrency.MainActor (Self) -> OperationResult) -> OperationResult {
        let _innoDIContainer = Self(_innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (throws)
    @_Concurrency.MainActor static func withOverrides<OperationResult>(_innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: @_Concurrency.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @_Concurrency.MainActor (Self) throws -> OperationResult) throws -> OperationResult {
        let _innoDIContainer = Self(_innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return try _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async)
    @_Concurrency.MainActor static func withOverrides<OperationResult>(_innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: @_Concurrency.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @_Concurrency.MainActor (Self) async -> OperationResult) async -> OperationResult {
        let _innoDIContainer = Self(_innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return await _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async throws)
    @_Concurrency.MainActor static func withOverrides<OperationResult>(_innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: @_Concurrency.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @_Concurrency.MainActor (Self) async throws -> OperationResult) async throws -> OperationResult {
        let _innoDIContainer = Self(_innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return try await _innoDIOperation(_innoDIContainer)
    }
}