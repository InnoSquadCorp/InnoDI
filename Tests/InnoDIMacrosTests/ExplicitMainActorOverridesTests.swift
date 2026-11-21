import Foundation
import InnoDITestSupport
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

@Suite("Explicit MainActor override isolation")
struct ExplicitMainActorOverridesTests {
    @Test(arguments: [
        ("", "@DIContainer", 2),
        ("", "@DIContainerRole(role: ContainerRole.local, mainActor: true)", 0),
        ("@MainActor", "@DIContainer", 0),
        ("@MainActor", "@DIContainerRole(role: ContainerRole.local, mainActor: true)", 0),
        ("@_Concurrency.MainActor", "@DIContainer", 0),
        // A custom global actor isolates the generated initializer the same
        // way, so the async overloads must inherit it too.
        ("@FeatureActor", "@DIContainer", 0),
        ("@Module.FeatureActor", "@DIContainer", 0),
        ("@FeatureActor", "@DIContainerRole(role: ContainerRole.local)", 0),
        ("@FeatureActor", "@DIContainerRole(role: ContainerRole.root)", 0),
    ])
    func inheritedIsolation(prefix: String, attribute: String, nonisolatedOverloads: Int) {
        var macros = DIContainerMacroTests.macros
        macros["DIContainerRole"] = DIContainerRoleMacro.self
        let result = expandMacroSource("\(prefix)\n\(attribute) struct Container {}", macros: macros)
        #expect(result.diagnostics.isEmpty)
        let count = result.expansion.components(separatedBy: "nonisolated(nonsending) static func withOverrides").count - 1
        #expect(count == nonisolatedOverloads)
        #expect(result.expansion.components(separatedBy: "static func withOverrides").count - 1 == 4)
    }
}
