
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

    init(viewModel: ViewModel? = nil) {
        self._override_viewModel = viewModel
    }

    struct Overrides {
        var viewModel: ViewModel? = nil
    }

    init(_ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(viewModel: overrides.viewModel)
    }

    static func withOverrides<T>(_ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> T) -> T {
        let container = Self(applyOverrides)
        return operation(container)
    }

    static func withOverrides<T>(_ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> T) throws -> T {
        let container = Self(applyOverrides)
        return try operation(container)
    }

    static func withOverrides<T>(_ applyOverrides: (inout Overrides) -> Void, operation: (Self) async -> T) async -> T {
        let container = Self(applyOverrides)
        return await operation(container)
    }

    static func withOverrides<T>(_ applyOverrides: (inout Overrides) -> Void, operation: (Self) async throws -> T) async throws -> T {
        let container = Self(applyOverrides)
        return try await operation(container)
    }
}