
struct Parent {
    @InnoDI._InnoDIProvideAccessor(recovery: false) var apply: Int

    typealias _InnoDIInputType_apply = Int
    @InnoDI._InnoDISubContainerAccessor(recovery: false)
    var child: Child

    // MARK: - Initialization
    init(apply: Int, child: Child? = nil, childOverrides: ((inout Child._InnoDIMountOverrides) -> Void)? = nil, _innoDITrace: DITraceContext = .disabled) {
        final class _InnoDIDeferredCell<T> {
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
        self._storage_apply = apply
        self._override_sub_child = child
        self._override_sub_apply_child = childOverrides
        let _innoDISubBuildCell_child = _InnoDIDeferredCell<Child>()
        self._innoDISubBuild_child = {
            _innoDISubBuildCell_child.resolve()
        }
        _innoDISubBuildCell_child.bindResolver { () -> Child in
            if let direct = child {
                return direct
            }
            if let _innoDIApply = childOverrides {
                return .init(apply: apply, _innoDITrace: _innoDITrace, _innoDIApply)
            }
            return .init(apply: apply, _innoDITrace: _innoDITrace)
        }
    }

    // MARK: - Overrides Builder
    struct Overrides {
        var child: Child? = nil
        var childOverrides: ((inout Child._InnoDIMountOverrides) -> Void)? = nil
        mutating func set<Value>(_ keyPath: Swift.WritableKeyPath<Self, Value?>, to value: Value) {
            self[keyPath: keyPath] = .some(value)
        }
        mutating func useDefault<Value>(_ keyPath: Swift.WritableKeyPath<Self, Value?>) {
            self[keyPath: keyPath] = .none
        }
    }

    typealias _InnoDIMountOverrides = Overrides

    // MARK: - Convenience Init with Overrides
    init(apply: Int, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(apply: apply, child: _innoDIOverrides.child, childOverrides: _innoDIOverrides.childOverrides, _innoDITrace: _innoDITrace)
    }

    // MARK: - withOverrides
    static func withOverrides<_InnoDIOperationResult>(apply: Int, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) -> _InnoDIOperationResult) -> _InnoDIOperationResult {
        let _innoDIContainer = Self(apply: apply, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (throws)
    static func withOverrides<_InnoDIOperationResult>(apply: Int, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) throws -> _InnoDIOperationResult) throws -> _InnoDIOperationResult {
        let _innoDIContainer = Self(apply: apply, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return try _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async)
    nonisolated(nonsending) static func withOverrides<_InnoDIOperationResult>(apply: Int, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async -> _InnoDIOperationResult) async -> _InnoDIOperationResult {
        let _innoDIContainer = Self(apply: apply, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return await _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async throws)
    nonisolated(nonsending) static func withOverrides<_InnoDIOperationResult>(apply: Int, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async throws -> _InnoDIOperationResult) async throws -> _InnoDIOperationResult {
        let _innoDIContainer = Self(apply: apply, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return try await _innoDIOperation(_innoDIContainer)
    }
}