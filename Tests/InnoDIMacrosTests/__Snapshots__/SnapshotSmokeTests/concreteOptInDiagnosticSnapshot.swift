
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: true)
    var apiClient: APIClient
}