import Foundation
import Testing

@testable import InnoDIBuildSupport

@Suite("ValidationCoordinatorLockPolicy environment overrides")
struct LockPolicyEnvTests {
    @Test("Missing environment keys yield default timings")
    func noOverrides() {
        var warnings: [String] = []
        let policy = ValidationCoordinatorLockPolicy(
            environment: [:],
            warningHandler: { warnings.append($0) }
        )
        let defaults = ValidationCoordinatorLockPolicy.default
        #expect(policy.maxWaitSeconds == defaults.maxWaitSeconds)
        #expect(policy.staleLockAgeSeconds == defaults.staleLockAgeSeconds)
        #expect(warnings.isEmpty)
    }

    @Test("Valid overrides are respected")
    func validOverrides() {
        var warnings: [String] = []
        let policy = ValidationCoordinatorLockPolicy(
            environment: [
                ValidationCoordinatorLockPolicy.EnvKey.lockTimeout: "45.5",
                ValidationCoordinatorLockPolicy.EnvKey.staleLockAge: "90"
            ],
            warningHandler: { warnings.append($0) }
        )
        #expect(policy.maxWaitSeconds == 45.5)
        #expect(policy.staleLockAgeSeconds == 90)
        #expect(warnings.isEmpty)
    }

    @Test("Invalid values fall back to defaults and emit a warning")
    func invalidOverrides() {
        var warnings: [String] = []
        let policy = ValidationCoordinatorLockPolicy(
            environment: [
                ValidationCoordinatorLockPolicy.EnvKey.lockTimeout: "not-a-number",
                ValidationCoordinatorLockPolicy.EnvKey.staleLockAge: "-5"
            ],
            warningHandler: { warnings.append($0) }
        )
        let defaults = ValidationCoordinatorLockPolicy.default
        #expect(policy.maxWaitSeconds == defaults.maxWaitSeconds)
        #expect(policy.staleLockAgeSeconds == defaults.staleLockAgeSeconds)
        #expect(warnings.count == 2)
        #expect(warnings.contains(where: { $0.contains("INNODI_LOCK_TIMEOUT") }))
        #expect(warnings.contains(where: { $0.contains("INNODI_STALE_LOCK_AGE") }))
    }

    @Test("Zero is rejected as a non-positive override")
    func zeroOverridesAreInvalid() {
        var warnings: [String] = []
        let policy = ValidationCoordinatorLockPolicy(
            environment: [
                ValidationCoordinatorLockPolicy.EnvKey.lockTimeout: "0",
                ValidationCoordinatorLockPolicy.EnvKey.staleLockAge: "0"
            ],
            warningHandler: { warnings.append($0) }
        )
        let defaults = ValidationCoordinatorLockPolicy.default
        #expect(policy.maxWaitSeconds == defaults.maxWaitSeconds)
        #expect(policy.staleLockAgeSeconds == defaults.staleLockAgeSeconds)
        #expect(warnings.count == 2)
        #expect(warnings.allSatisfy { $0.contains("0") })
    }

    @Test("Non-finite values fall back to defaults and warn")
    func nonFiniteOverridesAreInvalid() {
        var warnings: [String] = []
        let policy = ValidationCoordinatorLockPolicy(
            environment: [
                ValidationCoordinatorLockPolicy.EnvKey.lockTimeout: "inf",
                ValidationCoordinatorLockPolicy.EnvKey.staleLockAge: "nan"
            ],
            warningHandler: { warnings.append($0) }
        )
        let defaults = ValidationCoordinatorLockPolicy.default
        #expect(policy.maxWaitSeconds == defaults.maxWaitSeconds)
        #expect(policy.staleLockAgeSeconds == defaults.staleLockAgeSeconds)
        #expect(warnings.count == 2)
        #expect(warnings.contains(where: { $0.contains("inf") }))
        #expect(warnings.contains(where: { $0.contains("nan") }))
    }

    @Test("Excessively large values fall back to defaults and warn")
    func hugeOverridesAreInvalid() {
        var warnings: [String] = []
        let policy = ValidationCoordinatorLockPolicy(
            environment: [
                ValidationCoordinatorLockPolicy.EnvKey.lockTimeout: "315360000",
                ValidationCoordinatorLockPolicy.EnvKey.staleLockAge: "315360000"
            ],
            warningHandler: { warnings.append($0) }
        )
        let defaults = ValidationCoordinatorLockPolicy.default
        #expect(policy.maxWaitSeconds == defaults.maxWaitSeconds)
        #expect(policy.staleLockAgeSeconds == defaults.staleLockAgeSeconds)
        #expect(warnings.count == 2)
        #expect(warnings.allSatisfy { $0.contains("315360000") })
    }

    @Test("Empty values are ignored without warning")
    func emptyValuesIgnored() {
        var warnings: [String] = []
        let policy = ValidationCoordinatorLockPolicy(
            environment: [
                ValidationCoordinatorLockPolicy.EnvKey.lockTimeout: "",
                ValidationCoordinatorLockPolicy.EnvKey.staleLockAge: ""
            ],
            warningHandler: { warnings.append($0) }
        )
        let defaults = ValidationCoordinatorLockPolicy.default
        #expect(policy.maxWaitSeconds == defaults.maxWaitSeconds)
        #expect(policy.staleLockAgeSeconds == defaults.staleLockAgeSeconds)
        #expect(warnings.isEmpty)
    }
}
