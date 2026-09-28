
struct AppContainer {
    struct Overrides {
        var custom: String
    }
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var userID: String

    // MARK: - Initialization
    init(userID: String, _innoDITrace: DITraceContext = .disabled) {
        self._storage_userID = userID
    }

    struct _InnoDIMountOverrides {
    }

    init(userID: String, _ _innoDIApplyOverrides: (inout _InnoDIMountOverrides) -> Void) {
        while true {
        }
    }
}