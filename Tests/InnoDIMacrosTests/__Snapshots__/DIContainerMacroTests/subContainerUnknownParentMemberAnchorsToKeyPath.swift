
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false) var config: AppConfig

    private var _storage_config: AppConfig? = nil
    var feature: FeatureContainer {
        get {
            return _storage_sub_feature
        }
    }

    private let _storage_sub_feature: FeatureContainer

    private let _override_sub_feature: FeatureContainer?

    private let _override_sub_apply_feature: ((inout FeatureContainer.Overrides) -> Void)?
}