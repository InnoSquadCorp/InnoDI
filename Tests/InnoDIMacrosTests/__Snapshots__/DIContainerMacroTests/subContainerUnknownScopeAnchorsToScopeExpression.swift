
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false) var config: AppConfig

    private var _storage_config: AppConfig? = nil
    var feature: FeatureContainer
}