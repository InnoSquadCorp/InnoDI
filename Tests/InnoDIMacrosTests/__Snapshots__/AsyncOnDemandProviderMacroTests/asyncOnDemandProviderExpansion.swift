
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false) var client: APIClient

    typealias _InnoDIInputType_client = APIClient
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var session: Session
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var profile: Profile

    // MARK: - Initialization
    init(client: APIClient, session: Session? = nil, profile: Profile? = nil, _innoDITrace: DITraceContext = .disabled) {
        let _innoDITraceOwner = _InnoDITraceOwner(
            context: _innoDITrace,
            containerType: Self.self
        )
        self._innoDITraceOwner_profile = _innoDITraceOwner
        self._storage_client = client
        let _innoDIOnDemandAsync_session: InnoDI._InnoDIAsyncSharedCell<Session> = if let _innoDIOverride = session {
            InnoDI._InnoDIAsyncSharedCell(
                traceOwner: _innoDITraceOwner,
                providerName: "session",
                value: _innoDIOverride
            )
        } else {
            InnoDI._InnoDIAsyncSharedCell(
                traceOwner: _innoDITraceOwner,
                providerName: "session"
            ) {
                try await { (client: APIClient) async throws in
                            try await Session.open(client: client)
                        }(client)
            }
        }
        self._storage_session = _innoDIOnDemandAsync_session
        let _innoDITraceSpan_profile = _innoDITraceOwner.start(
            member: "profile"
        )
        let _innoDITask_profile: _Concurrency.Task<Profile, Swift.Error> = .init {
            if let override = profile {
                return _innoDITraceOwner.overridden(
                    member: "profile",
                    value: override,
                    span: _innoDITraceSpan_profile
                )
            }
            return try await _innoDITraceOwner.withResolution(
                span: _innoDITraceSpan_profile
            ) {
                try await { (session: Session) async throws in
                    Profile(session: session)
                }(try await _innoDIOnDemandAsync_session.value())
            }
        }
        self._storage_task_profile = _innoDITask_profile
    }

    // MARK: - Async Provider Lifetime
    nonisolated(nonsending) func closeAsyncProviders() async {
        await self._storage_session!.close()
    }

    // MARK: - Overrides Builder
    struct Overrides {
        var session: Session? = nil
        var profile: Profile? = nil
        mutating func set<Value>(_ keyPath: Swift.WritableKeyPath<Self, Value?>, to value: Value) {
            self[keyPath: keyPath] = .some(value)
        }
        mutating func useDefault<Value>(_ keyPath: Swift.WritableKeyPath<Self, Value?>) {
            self[keyPath: keyPath] = .none
        }
    }

    typealias _InnoDIMountOverrides = Overrides

    // MARK: - Convenience Init with Overrides
    init(client: APIClient, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(client: client, session: _innoDIOverrides.session, profile: _innoDIOverrides.profile, _innoDITrace: _innoDITrace)
    }

    // MARK: - withOverrides
    static func withOverrides<OperationResult>(client: APIClient, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) -> OperationResult) -> OperationResult {
        let _innoDIContainer = Self(client: client, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (throws)
    static func withOverrides<OperationResult>(client: APIClient, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) throws -> OperationResult) throws -> OperationResult {
        let _innoDIContainer = Self(client: client, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return try _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async)
    nonisolated(nonsending) static func withOverrides<OperationResult>(client: APIClient, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async -> OperationResult) async -> OperationResult {
        let _innoDIContainer = Self(client: client, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return await _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async throws)
    nonisolated(nonsending) static func withOverrides<OperationResult>(client: APIClient, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async throws -> OperationResult) async throws -> OperationResult {
        let _innoDIContainer = Self(client: client, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return try await _innoDIOperation(_innoDIContainer)
    }
}