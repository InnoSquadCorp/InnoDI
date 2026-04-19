
struct AppContainer {
    var config: Config {
        get {
            return _storage_config
        }
    }

    private let _storage_config: Config

    @MainActor init(config: Config) {
        self._storage_config = config
    }
}