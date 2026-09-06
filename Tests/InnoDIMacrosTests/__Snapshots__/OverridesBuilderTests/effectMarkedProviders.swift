
public struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    public var apiClient: APIClient
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    public var viewModel: ViewModel

    // MARK: - Initialization
    public init(apiClient: APIClient? = nil, viewModel: ViewModel? = nil) {
        self._storage_apiClient = apiClient ?? APIClient()
        self._override_viewModel = viewModel
    }

    // MARK: - Overrides Builder
    public struct Overrides: InnoDI.DIOverrideEffectValidating {
        public var apiClient: APIClient? = nil
        public var viewModel: ViewModel? = nil
        public static let requiredEffectOverrides: [InnoDI.DIProviderEffectRequirement] = [InnoDI.DIProviderEffectRequirement(providerName: "apiClient", effect: .sideEffect)]
        public var missingEffectOverrides: [InnoDI.DIProviderEffectRequirement] {
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

    public typealias _InnoDIMountOverrides = Overrides

    // MARK: - Convenience Init with Overrides
    public init(_ _innoDIApplyOverrides: (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(apiClient: _innoDIOverrides.apiClient, viewModel: _innoDIOverrides.viewModel)
    }

    // MARK: - withOverrides
    public static func withOverrides<OperationResult>(_ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) -> OperationResult) -> OperationResult {
        let _innoDIContainer = Self(_innoDIApplyOverrides)
        return _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (throws)
    public static func withOverrides<OperationResult>(_ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) throws -> OperationResult) throws -> OperationResult {
        let _innoDIContainer = Self(_innoDIApplyOverrides)
        return try _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async)
    public nonisolated(nonsending) static func withOverrides<OperationResult>(_ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async -> OperationResult) async -> OperationResult {
        let _innoDIContainer = Self(_innoDIApplyOverrides)
        return await _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async throws)
    public nonisolated(nonsending) static func withOverrides<OperationResult>(_ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async throws -> OperationResult) async throws -> OperationResult {
        let _innoDIContainer = Self(_innoDIApplyOverrides)
        return try await _innoDIOperation(_innoDIContainer)
    }
}