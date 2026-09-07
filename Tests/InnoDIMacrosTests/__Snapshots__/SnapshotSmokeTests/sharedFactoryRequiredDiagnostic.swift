
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: true)
    var apiClient: any APIClientProtocol
}