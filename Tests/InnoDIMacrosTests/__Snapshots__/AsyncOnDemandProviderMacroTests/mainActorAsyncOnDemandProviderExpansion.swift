
struct AppContainer {
    @_Concurrency.MainActor @InnoDI._InnoDIProvideAccessor(recovery: false) var store: Store
    @_Concurrency.MainActor @InnoDI._InnoDIProvideAccessor(recovery: false)
    var snapshot: Snapshot

    // MARK: - Initialization
    @_Concurrency.MainActor init(store: Store, snapshot: Snapshot? = nil, _innoDITrace: DITraceContext = .disabled) {
        let _innoDITraceOwner = _InnoDITraceOwner(
            context: _innoDITrace,
            containerType: Self.self
        )
        self._storage_store = store
        let _innoDIOnDemandAsync_snapshot: InnoDI._InnoDIAsyncSharedCell<Snapshot> = if let _innoDIOverride = snapshot {
            InnoDI._InnoDIAsyncSharedCell(
                traceOwner: _innoDITraceOwner,
                providerName: "snapshot",
                value: _innoDIOverride
            )
        } else {
            InnoDI._InnoDIAsyncSharedCell(
                traceOwner: _innoDITraceOwner,
                providerName: "snapshot"
            ) { @_Concurrency.MainActor in
                await { (store: Store) async in
                    await store.load()
                }(store)
            }
        }
        self._storage_snapshot = _innoDIOnDemandAsync_snapshot
    }

    // MARK: - Async Provider Lifetime
    @_Concurrency.MainActor
    func closeAsyncProviders() async {
        await self._storage_snapshot!.close()
    }

    // MARK: - Overrides Builder
    @_Concurrency.MainActor struct Overrides {
        var snapshot: Snapshot? = nil
        mutating func set<Value>(_ keyPath: Swift.WritableKeyPath<Self, Value?>, to value: Value) {
            self[keyPath: keyPath] = .some(value)
        }
        mutating func useDefault<Value>(_ keyPath: Swift.WritableKeyPath<Self, Value?>) {
            self[keyPath: keyPath] = .none
        }
    }

    typealias _InnoDIMountOverrides = Overrides

    // MARK: - Convenience Init with Overrides
    @_Concurrency.MainActor init(store: Store, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: @_Concurrency.MainActor (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(store: store, snapshot: _innoDIOverrides.snapshot, _innoDITrace: _innoDITrace)
    }

    // MARK: - withOverrides
    @_Concurrency.MainActor static func withOverrides<OperationResult>(store: Store, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: @_Concurrency.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @_Concurrency.MainActor (Self) -> OperationResult) -> OperationResult {
        let _innoDIContainer = Self(store: store, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (throws)
    @_Concurrency.MainActor static func withOverrides<OperationResult>(store: Store, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: @_Concurrency.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @_Concurrency.MainActor (Self) throws -> OperationResult) throws -> OperationResult {
        let _innoDIContainer = Self(store: store, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return try _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async)
    @_Concurrency.MainActor static func withOverrides<OperationResult>(store: Store, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: @_Concurrency.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @_Concurrency.MainActor (Self) async -> OperationResult) async -> OperationResult {
        let _innoDIContainer = Self(store: store, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return await _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async throws)
    @_Concurrency.MainActor static func withOverrides<OperationResult>(store: Store, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: @_Concurrency.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @_Concurrency.MainActor (Self) async throws -> OperationResult) async throws -> OperationResult {
        let _innoDIContainer = Self(store: store, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return try await _innoDIOperation(_innoDIContainer)
    }
}