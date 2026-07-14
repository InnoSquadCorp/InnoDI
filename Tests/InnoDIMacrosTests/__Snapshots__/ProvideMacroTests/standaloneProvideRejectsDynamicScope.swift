struct PlainContainer {
    var service: Service {
        get {
            Swift.preconditionFailure("Invalid @Provide scope")
        }
    }
}