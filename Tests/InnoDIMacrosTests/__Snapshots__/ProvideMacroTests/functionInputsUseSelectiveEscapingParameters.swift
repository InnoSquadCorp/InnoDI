typealias Handler = @Sendable () -> Void
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var aliasedHandler: Handler

    private var _storage_aliasedHandler: Handler? = nil
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var directHandler: @Sendable () -> Void

    private var _storage_directHandler: (@Sendable () -> Void)? = nil

    // MARK: - Initialization
    init(aliasedHandler: @escaping Handler, directHandler: @escaping @Sendable () -> Void) {
        self._storage_aliasedHandler = aliasedHandler
        self._storage_directHandler = directHandler
    }

    // MARK: - Overrides Builder
    struct Overrides {
    }

    // MARK: - Convenience Init with Overrides
    init(aliasedHandler: @escaping Handler, directHandler: @escaping @Sendable () -> Void, _ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(aliasedHandler: aliasedHandler, directHandler: directHandler)
    }

    // MARK: - withOverrides
    static func withOverrides<OperationResult>(aliasedHandler: @escaping Handler, directHandler: @escaping @Sendable () -> Void, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> OperationResult) -> OperationResult {
        let container = Self(aliasedHandler: aliasedHandler, directHandler: directHandler, applyOverrides)
        return operation(container)
    }

    // MARK: - withOverrides (throws)
    static func withOverrides<OperationResult>(aliasedHandler: @escaping Handler, directHandler: @escaping @Sendable () -> Void, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> OperationResult) throws -> OperationResult {
        let container = Self(aliasedHandler: aliasedHandler, directHandler: directHandler, applyOverrides)
        return try operation(container)
    }

    // MARK: - withOverrides (async)
    nonisolated(nonsending) static func withOverrides<OperationResult>(aliasedHandler: @escaping Handler, directHandler: @escaping @Sendable () -> Void, _ applyOverrides: (inout Overrides) -> Void, operation: nonisolated(nonsending) (Self) async -> OperationResult) async -> OperationResult {
        let container = Self(aliasedHandler: aliasedHandler, directHandler: directHandler, applyOverrides)
        return await operation(container)
    }

    // MARK: - withOverrides (async throws)
    nonisolated(nonsending) static func withOverrides<OperationResult>(aliasedHandler: @escaping Handler, directHandler: @escaping @Sendable () -> Void, _ applyOverrides: (inout Overrides) -> Void, operation: nonisolated(nonsending) (Self) async throws -> OperationResult) async throws -> OperationResult {
        let container = Self(aliasedHandler: aliasedHandler, directHandler: directHandler, applyOverrides)
        return try await operation(container)
    }
}