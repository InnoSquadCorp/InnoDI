
struct AppContainer {
    var apiClient: APIClient {
        get {
            return _storage_apiClient
        }
    }

    private let _storage_apiClient: APIClient
    var viewModel: ViewModel {
        get async {
            if let override = _override_viewModel {
                return override
            }
            return await { (apiClient: APIClient) async in
                await ViewModel.load(apiClient: apiClient)
            }(self.apiClient)
        }
    }

    private let _override_viewModel: ViewModel?

    init(apiClient: APIClient, viewModel: ViewModel? = nil) {
        self._storage_apiClient = apiClient
        self._override_viewModel = viewModel
    }
}