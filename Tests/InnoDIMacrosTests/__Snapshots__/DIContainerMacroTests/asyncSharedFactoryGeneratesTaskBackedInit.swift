
struct AppContainer {
    var config: Config {
        get {
            return _storage_config
        }
    }

    private let _storage_config: Config
    var service: Service {
        get async {
            return await _storage_task_service.value
        }
    }

    private let _storage_task_service: Task<Service, Never>

    init(config: Config, service: Service? = nil) {
        self._storage_config = config
        let _resolved_config = config
        let _task_service = Task<Service, Never> {
            if let override = service {
                return override
            }
            return await { (config: Config) async in
                Service(config: config)
            }(_resolved_config)
        }
        self._storage_task_service = _task_service
        let _resolved_task_service = _task_service
    }
}