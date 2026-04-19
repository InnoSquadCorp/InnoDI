
struct AppContainer {
    var serviceA: ServiceA {
        get {
            if let override = _override_serviceA {
                return override
            }
            return { (serviceB: ServiceB) in
                    ServiceA(serviceB: serviceB)
                }(self.serviceB)
        }
    }

    private let _override_serviceA: ServiceA?
    var serviceB: ServiceB {
        get {
            if let override = _override_serviceB {
                return override
            }
            return { (serviceA: ServiceA) in
                    ServiceB(serviceA: serviceA)
                }(self.serviceA)
        }
    }

    private let _override_serviceB: ServiceB?

    init(serviceA: ServiceA? = nil, serviceB: ServiceB? = nil) {
        self._override_serviceA = serviceA
        self._override_serviceB = serviceB
    }
}