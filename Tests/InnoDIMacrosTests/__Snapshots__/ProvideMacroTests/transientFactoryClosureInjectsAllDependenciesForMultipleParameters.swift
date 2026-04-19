
struct AppContainer {
    var apiClient: APIClient {
        get {
            return _storage_apiClient
        }
    }

    private let _storage_apiClient: APIClient
    var logger: Logger {
        get {
            return _storage_logger
        }
    }

    private let _storage_logger: Logger
    var viewModel: ViewModel {
        get {
            if let override = _override_viewModel {
                return override
            }
            return { (apiClient: APIClient, logger: Logger) in
                ViewModel(apiClient: apiClient, logger: logger)
            }(self.apiClient, self.logger)
        }
    }

    private let _override_viewModel: ViewModel?

    init(apiClient: APIClient, logger: Logger, viewModel: ViewModel? = nil) {
        self._storage_apiClient = apiClient
        self._storage_logger = logger
        self._override_viewModel = viewModel
    }
}