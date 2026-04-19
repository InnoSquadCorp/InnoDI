
struct AppContainer {
    var service: Service {
        get {
            if let override = _override_service {
                return override
            }
            return Service()
        }
    }

    private let _override_service: Service?

    @MainActor init(service: Service? = nil) {
        self._override_service = service
    }
}