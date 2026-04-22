import Testing

/// Shared custom test tags used to group slower or validation-heavy suites.
public extension Tag {
    /// Marks slower-running integration or build-oriented tests.
    @Tag static var slow: Self
    /// Marks hierarchy validation-focused tests and regressions.
    @Tag static var hierarchyValidation: Self
}
