
struct AppContainer {
    var apiClient: APIClient {
        get {
            return _storage_apiClient
        }
    }

    private let _storage_apiClient: APIClient
    var viewModel: ViewModel {
        get {
            if let override = _override_viewModel {
                return override
            }
            return { (missing: APIClient) in
                ViewModel(apiClient: missing)
            }(self.missing)
        }
    }

    private let _override_viewModel: ViewModel?
}