let requestedScope: DIScope = .shared
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: true)
    var service: Service
}