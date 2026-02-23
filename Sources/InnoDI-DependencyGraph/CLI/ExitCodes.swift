enum ExitCode {
    static let success: Int32 = 0
    static let failure: Int32 = 1
    static let noContainers: Int32 = 1
    static let ioError: Int32 = 2
    static let dagValidationFailure: Int32 = 3
}
