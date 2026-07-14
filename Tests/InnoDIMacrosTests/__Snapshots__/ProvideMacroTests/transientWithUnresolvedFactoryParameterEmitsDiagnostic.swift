
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var apiClient: APIClient

    private var _storage_apiClient: APIClient? = nil
    @InnoDI._InnoDIProvideAccessor(recovery: true)
    var viewModel: ViewModel
}