
struct AppContainer {
    var config: Config {
        get {
            return _storage_config
        }
    }

    private let _storage_config: Config
    var viewModel: ViewModel {
        get {
            if let override = _override_viewModel {
                return override
            }
            return ViewModel(config: self.config)
        }
    }

    private let _override_viewModel: ViewModel?

    init(config: Config, viewModel: ViewModel? = nil) {
        self._storage_config = config
        self._override_viewModel = viewModel
    }
}