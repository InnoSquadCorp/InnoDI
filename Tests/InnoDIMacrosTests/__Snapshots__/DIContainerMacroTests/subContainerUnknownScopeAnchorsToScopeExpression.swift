
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false) var config: AppConfig
    var feature: FeatureContainer
}