enum ExitCode {
    static let success: Int32 = 0
    static let failure: Int32 = 1
    static let ioError: Int32 = 2
    static let dagValidationFailure: Int32 = 3
    /// Distinct from `failure` so tooling can tell "the workspace has no
    /// `@DIContainer` yet" apart from a genuine error.
    static let noContainers: Int32 = 4
}
