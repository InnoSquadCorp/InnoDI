
struct AppContainer {
    var feature: FeatureContainer {
        get {
            return _storage_sub_feature
        }
    }

    private let _storage_sub_feature: FeatureContainer

    private let _override_sub_feature: FeatureContainer?

    private let _override_sub_apply_feature: ((inout FeatureContainer.Overrides) -> Void)?

    init(feature: FeatureContainer? = nil, featureOverrides: ((inout FeatureContainer.Overrides) -> Void)? = nil) {
        if let direct = feature {
            self._storage_sub_feature = direct
         } else if let apply = featureOverrides {
            self._storage_sub_feature = FeatureContainer(apply)
         } else {
            self._storage_sub_feature = FeatureContainer()
        }
        self._override_sub_feature = feature
        self._override_sub_apply_feature = featureOverrides
    }

    struct Overrides {
        var feature: FeatureContainer? = nil
        var featureOverrides: ((inout FeatureContainer.Overrides) -> Void)? = nil
    }

    init(_ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(feature: overrides.feature, featureOverrides: overrides.featureOverrides)
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