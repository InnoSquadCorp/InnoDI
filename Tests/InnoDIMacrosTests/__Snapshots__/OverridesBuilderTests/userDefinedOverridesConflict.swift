
struct AppContainer {
    struct Overrides {
        var custom: String
    }
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var userID: String
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var apiClient: APIClient

    // MARK: - Initialization
    init(userID: String, apiClient: APIClient? = nil, _innoDITrace: DITraceContext = .disabled) {
        let _innoDITraceOwner = _InnoDITraceOwner(
            context: _innoDITrace,
            containerType: Self.self
        )
        self._innoDITraceOwner_apiClient = _innoDITraceOwner
        self._storage_userID = userID
        if let _innoDIOverride = apiClient {
            self._storage_apiClient = _innoDITraceOwner.overridden(
                member: "apiClient",
                value: _innoDIOverride
            )
        } else {
            let _innoDITraceSpan_apiClient = _innoDITraceOwner.start(
                member: "apiClient"
            )
            let _innoDIResolved_apiClient = APIClient()
            _innoDITraceOwner.finish(.success, span: _innoDITraceSpan_apiClient)
            self._storage_apiClient = _innoDIResolved_apiClient
        }
    }

    struct _InnoDIMountOverrides {
    }

    init(userID: String, _ _innoDIApplyOverrides: (inout _InnoDIMountOverrides) -> Void) {
        while true {
        }
    }
}