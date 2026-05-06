@Provide(.shared, factory: { (baseURL: String) in
    APIClient(baseURL: baseURL)
}, concrete: true)
var apiClient: APIClient
