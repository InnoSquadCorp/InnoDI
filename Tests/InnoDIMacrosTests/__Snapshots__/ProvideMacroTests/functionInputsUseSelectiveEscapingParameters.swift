typealias Handler = @Sendable () -> Void
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var aliasedHandler: Handler
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var directHandler: @Sendable () -> Void

    // MARK: - Initialization
    init(aliasedHandler: @escaping Handler, directHandler: @escaping @Sendable () -> Void) {
        self._storage_aliasedHandler = aliasedHandler
        self._storage_directHandler = directHandler
    }

    // MARK: - Overrides Builder
    struct Overrides {
    }

    typealias _InnoDIMountOverrides = Overrides

    // MARK: - Convenience Init with Overrides
    init(aliasedHandler: @escaping Handler, directHandler: @escaping @Sendable () -> Void, _ _innoDIApplyOverrides: (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(aliasedHandler: aliasedHandler, directHandler: directHandler)
    }

    // MARK: - withOverrides
    static func withOverrides<OperationResult>(aliasedHandler: @escaping Handler, directHandler: @escaping @Sendable () -> Void, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) -> OperationResult) -> OperationResult {
        let _innoDIContainer = Self(aliasedHandler: aliasedHandler, directHandler: directHandler, _innoDIApplyOverrides)
        return _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (throws)
    static func withOverrides<OperationResult>(aliasedHandler: @escaping Handler, directHandler: @escaping @Sendable () -> Void, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) throws -> OperationResult) throws -> OperationResult {
        let _innoDIContainer = Self(aliasedHandler: aliasedHandler, directHandler: directHandler, _innoDIApplyOverrides)
        return try _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async)
    nonisolated(nonsending) static func withOverrides<OperationResult>(aliasedHandler: @escaping Handler, directHandler: @escaping @Sendable () -> Void, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async -> OperationResult) async -> OperationResult {
        let _innoDIContainer = Self(aliasedHandler: aliasedHandler, directHandler: directHandler, _innoDIApplyOverrides)
        return await _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async throws)
    nonisolated(nonsending) static func withOverrides<OperationResult>(aliasedHandler: @escaping Handler, directHandler: @escaping @Sendable () -> Void, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async throws -> OperationResult) async throws -> OperationResult {
        let _innoDIContainer = Self(aliasedHandler: aliasedHandler, directHandler: directHandler, _innoDIApplyOverrides)
        return try await _innoDIOperation(_innoDIContainer)
    }
}