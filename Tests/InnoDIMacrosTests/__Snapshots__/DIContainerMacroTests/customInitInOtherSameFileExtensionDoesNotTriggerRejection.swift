
struct AppContainer {
    var config: Config {
        get {
            return _storage_config
        }
    }

    private let _storage_config: Config

    init(config: Config) {
        self._storage_config = config
    }
}

struct Helper {
    let value: Int
}

extension Helper {
    init(value: Int, doubled: Bool) {
        self.init(value: value * (doubled ? 2 : 1))
    }
}