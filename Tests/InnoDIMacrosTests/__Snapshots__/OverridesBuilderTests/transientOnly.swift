
struct AppContainer {
    var viewModel: ViewModel {
        get {
            if let override = _override_viewModel {
                return override
            }
            return {
                ViewModel()
            }()
        }
    }

    private let _override_viewModel: ViewModel?

    // MARK: - Initialization
    init(viewModel: ViewModel? = nil) {
        self._override_viewModel = viewModel
    }

    // MARK: - Overrides Builder
    struct Overrides {
        var viewModel: ViewModel? = nil
    }

    // MARK: - Convenience Init with Overrides
    init(_ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(viewModel: overrides.viewModel)
    }

    // MARK: - withOverrides
    static func withOverrides<OperationResult>(_ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> OperationResult) -> OperationResult {
        let container = Self(applyOverrides)
        return operation(container)
    }

    // MARK: - withOverrides (throws)
    static func withOverrides<OperationResult>(_ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> OperationResult) throws -> OperationResult {
        let container = Self(applyOverrides)
        return try operation(container)
    }

    // MARK: - withOverrides (async)
    static func withOverrides<OperationResult>(_ applyOverrides: (inout Overrides) -> Void, operation: (Self) async -> OperationResult) async -> OperationResult {
        let container = Self(applyOverrides)
        return await operation(container)
    }

    // MARK: - withOverrides (async throws)
    static func withOverrides<OperationResult>(_ applyOverrides: (inout Overrides) -> Void, operation: (Self) async throws -> OperationResult) async throws -> OperationResult {
        let container = Self(applyOverrides)
        return try await operation(container)
    }
}