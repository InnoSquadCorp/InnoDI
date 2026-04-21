
struct AppContainer {
    var config: AppConfig {
        get {
            return _storage_config
        }
    }

    private let _storage_config: AppConfig
    var feature: FeatureContainer
}