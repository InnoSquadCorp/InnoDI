
struct FeatureComponent {
    enum Mode { case a, b 
}
    struct Settings {}
    typealias Handler = (Mode) -> Void
    @InnoDI._InnoDIProvideAccessor(recovery: false) var mode: Mode

    typealias _InnoDIInputType_mode = Mode
    @InnoDI._InnoDIProvideAccessor(recovery: false) var optionalMode: Mode?

    typealias _InnoDIInputType_optionalMode = Mode?
    @InnoDI._InnoDIProvideAccessor(recovery: false) var modes: [Mode]

    typealias _InnoDIInputType_modes = [Mode]
    @InnoDI._InnoDIProvideAccessor(recovery: false) var settings: [Mode: Settings]

    typealias _InnoDIInputType_settings = [Mode: Settings]
    @InnoDI._InnoDIProvideAccessor(recovery: false) var onChange: (Mode) -> Void

    typealias _InnoDIInputType_onChange = (Mode) -> Void
    @InnoDI._InnoDIProvideAccessor(recovery: false) var handler: Handler

    typealias _InnoDIInputType_handler = Handler
    @InnoDI._InnoDIProvideAccessor(recovery: false) var selfMode: Self.Mode

    typealias _InnoDIInputType_selfMode = Self.Mode
    @InnoDI._InnoDIProvideAccessor(recovery: false) var external: Swift.Optional<Outer.Mode>

    typealias _InnoDIInputType_external = Swift.Optional<Outer.Mode>
    @InnoDI._InnoDIProvideAccessor(recovery: false) var label: String

    typealias _InnoDIInputType_label = String

    init(mode: Mode, optionalMode: Mode?, modes: [Mode], settings: [Mode: Settings], onChange: @escaping (Mode) -> Void, handler: @escaping Handler, selfMode: Self.Mode, external: Swift.Optional<Outer.Mode>, label: String, _innoDITrace: DITraceContext = .disabled) {
        self._storage_mode = mode
        self._storage_optionalMode = optionalMode
        self._storage_modes = modes
        self._storage_settings = settings
        self._storage_onChange = onChange
        self._storage_handler = handler
        self._storage_selfMode = selfMode
        self._storage_external = external
        self._storage_label = label
    }

    // MARK: - Overrides Builder
    struct Overrides {
    }

    typealias _InnoDIMountOverrides = Overrides

    // MARK: - Convenience Init with Overrides
    init(mode: Mode, optionalMode: Mode?, modes: [Mode], settings: [Mode: Settings], onChange: @escaping (Mode) -> Void, handler: @escaping Handler, selfMode: Self.Mode, external: Swift.Optional<Outer.Mode>, label: String, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(mode: mode, optionalMode: optionalMode, modes: modes, settings: settings, onChange: onChange, handler: handler, selfMode: selfMode, external: external, label: label, _innoDITrace: _innoDITrace)
    }

    // MARK: - withOverrides
    static func withOverrides<_InnoDIOperationResult>(mode: Mode, optionalMode: Mode?, modes: [Mode], settings: [Mode: Settings], onChange: @escaping (Mode) -> Void, handler: @escaping Handler, selfMode: Self.Mode, external: Swift.Optional<Outer.Mode>, label: String, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) -> _InnoDIOperationResult) -> _InnoDIOperationResult {
        let _innoDIContainer = Self(mode: mode, optionalMode: optionalMode, modes: modes, settings: settings, onChange: onChange, handler: handler, selfMode: selfMode, external: external, label: label, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (throws)
    static func withOverrides<_InnoDIOperationResult>(mode: Mode, optionalMode: Mode?, modes: [Mode], settings: [Mode: Settings], onChange: @escaping (Mode) -> Void, handler: @escaping Handler, selfMode: Self.Mode, external: Swift.Optional<Outer.Mode>, label: String, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) throws -> _InnoDIOperationResult) throws -> _InnoDIOperationResult {
        let _innoDIContainer = Self(mode: mode, optionalMode: optionalMode, modes: modes, settings: settings, onChange: onChange, handler: handler, selfMode: selfMode, external: external, label: label, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return try _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async)
    nonisolated(nonsending) static func withOverrides<_InnoDIOperationResult>(mode: Mode, optionalMode: Mode?, modes: [Mode], settings: [Mode: Settings], onChange: @escaping (Mode) -> Void, handler: @escaping Handler, selfMode: Self.Mode, external: Swift.Optional<Outer.Mode>, label: String, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async -> _InnoDIOperationResult) async -> _InnoDIOperationResult {
        let _innoDIContainer = Self(mode: mode, optionalMode: optionalMode, modes: modes, settings: settings, onChange: onChange, handler: handler, selfMode: selfMode, external: external, label: label, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return await _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async throws)
    nonisolated(nonsending) static func withOverrides<_InnoDIOperationResult>(mode: Mode, optionalMode: Mode?, modes: [Mode], settings: [Mode: Settings], onChange: @escaping (Mode) -> Void, handler: @escaping Handler, selfMode: Self.Mode, external: Swift.Optional<Outer.Mode>, label: String, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async throws -> _InnoDIOperationResult) async throws -> _InnoDIOperationResult {
        let _innoDIContainer = Self(mode: mode, optionalMode: optionalMode, modes: modes, settings: settings, onChange: onChange, handler: handler, selfMode: selfMode, external: external, label: label, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return try await _innoDIOperation(_innoDIContainer)
    }

    // MARK: - Initialization
    init(
        dependencies _innoDIDependencies: any FeatureComponentDependencies,
        _ _innoDIApplyOverrides: (inout Overrides) -> Void = { _ in
        }
    ) {
        self.init(mode: _innoDIDependencies.mode, optionalMode: _innoDIDependencies.optionalMode, modes: _innoDIDependencies.modes, settings: _innoDIDependencies.settings, onChange: _innoDIDependencies.onChange, handler: _innoDIDependencies.handler, selfMode: _innoDIDependencies.selfMode, external: _innoDIDependencies.external, label: _innoDIDependencies.label, _innoDITrace: .disabled, _innoDIApplyOverrides)
    }

    init(
        dependencies _innoDIDependencies: any FeatureComponentDependencies,
        _innoDITrace: DITraceContext,
        _ _innoDIApplyOverrides: (inout Overrides) -> Void = { _ in
        }
    ) {
        self.init(mode: _innoDIDependencies.mode, optionalMode: _innoDIDependencies.optionalMode, modes: _innoDIDependencies.modes, settings: _innoDIDependencies.settings, onChange: _innoDIDependencies.onChange, handler: _innoDIDependencies.handler, selfMode: _innoDIDependencies.selfMode, external: _innoDIDependencies.external, label: _innoDIDependencies.label, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
    }
}

protocol FeatureComponentDependencies {
    var mode: FeatureComponent.Mode {
        get
    }
    var optionalMode: FeatureComponent.Mode? {
        get
    }
    var modes: [FeatureComponent.Mode] {
        get
    }
    var settings: [FeatureComponent.Mode: FeatureComponent.Settings] {
        get
    }
    var onChange: (FeatureComponent.Mode) -> Void {
        get
    }
    var handler: FeatureComponent.Handler {
        get
    }
    var selfMode: FeatureComponent.Mode {
        get
    }
    var external: Swift.Optional<Outer.Mode> {
        get
    }
    var label: String {
        get
    }
}

extension FeatureComponent: InnoDI._InnoDIComponentMountable {
    typealias _InnoDIComponentDependencies = any FeatureComponentDependencies
    typealias _InnoDIComponentOverrides = Overrides
}