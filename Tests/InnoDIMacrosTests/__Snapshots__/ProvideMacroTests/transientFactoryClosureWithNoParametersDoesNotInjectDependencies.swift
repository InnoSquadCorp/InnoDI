
struct AppContainer {
    var viewModel: ViewModel {
        get {
            if let override = _override_viewModel {
                return override
            }
            return {
                ViewModel()
            }()
        }
    }

    private let _override_viewModel: ViewModel?

    init(viewModel: ViewModel? = nil) {
        self._override_viewModel = viewModel
    }
}