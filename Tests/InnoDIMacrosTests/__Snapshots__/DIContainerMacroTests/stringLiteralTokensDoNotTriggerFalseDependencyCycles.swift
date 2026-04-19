
struct AppContainer {
    var a: ServiceA {
        get {
            return _storage_a
        }
    }

    private let _storage_a: ServiceA
    var b: ServiceB {
        get {
            return _storage_b
        }
    }

    private let _storage_b: ServiceB

    init(a: ServiceA? = nil, b: ServiceB? = nil) {
        self._storage_a = a ?? ServiceA(name: "b")
        self._storage_b = b ?? ServiceB(name: "a")
    }
}