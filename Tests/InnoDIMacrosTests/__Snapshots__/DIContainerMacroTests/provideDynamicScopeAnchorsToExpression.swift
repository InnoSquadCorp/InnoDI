let requestedScope: DIScope = .shared
struct AppContainer {
    var service: Service {
        get {
            Swift.preconditionFailure("Invalid @Provide scope")
        }
    }
}