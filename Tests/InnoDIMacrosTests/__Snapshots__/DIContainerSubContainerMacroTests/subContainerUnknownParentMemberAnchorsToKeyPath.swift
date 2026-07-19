
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false) var config: AppConfig
    @InnoDI._InnoDISubContainerAccessor(recovery: true)
    var feature: FeatureContainer
}