
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false) var config: AppConfig
    @InnoDI._InnoDIProvideAccessor(recovery: false) var request: Request
    @InnoDI._InnoDISubContainerAccessor(recovery: true)
    var feature: FeatureContainer
}