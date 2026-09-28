import SwiftParser
import SwiftSyntax
import Testing

@testable import InnoDIMacros

@Suite("Code generation preflight parity")
struct CodegenPreflightTests {
    @Test("Validation retains emission invariant failures", arguments: [
        "@Provide(.shared) var value: Int",
        "@Provide(.shared, factory: { (missing: Int) in missing }) var value: Int",
        "@Provide(.shared, factory: { (missing: Lazy<Int>) in missing.value }) var value: Int",
        "@Provide(.shared, factory: { (missing: Provider<Int>) in missing.get() }) var value: Int",
        "@Provide(.shared, asyncFactory: { (missing: Int) in missing }) var value: Int",
        "@Provide(.shared, Service.self, with: [\\Self.missing]) var value: Service",
        """
        @Provide(.shared, factory: { (a: Provider<Int>) in a }) var root: Provider<Int>
        @Provide(.transient, factory: { (b: Int) in b }) var a: Int
        @Provide(.transient, factory: { (a: Int) in a }) var b: Int
        """,
    ])
    func rejectsTheSameInvalidModel(_ members: String) throws {
        // Deliberately bypass semantic validation: these are the defensive
        // codegen invariants the recovery role must still exercise.
        let model = try parse(members)
        let emittedError = try failure { _ = try DIContainerCodeGenerator.generateAll(for: model) }
        let preflightError = try failure { try DIContainerCodeGenerator.validateInitialization(for: model) }
        #expect(preflightError == emittedError)
    }

    @Test("Valid preflight leaves emission unchanged", arguments: [
        "",
        "@Input var value: Int",
        """
        @Input var input: Int
        @Provide(.shared, factory: { (input: Int) in input + 1 }) var value: Int
        @SubContainer(scope: .shared, with: [], featureRoot: Root.self) var child: Child
        """,
        """
        @Provide(.shared, initialization: .onDemand, factory: 1) var first: Int
        @Provide(.shared, initialization: .onDemand, factory: { (first: Int) in first + 1 }) var second: Int
        @Provide(.shared, asyncFactory: { (second: Int) in second + 1 }) var third: Int
        """,
        """
        @Input var input: Int
        @Provide(.transient, factory: { (input: Int) in input }) var value: Int
        @SubContainer(scope: .transient, with: [\\.value]) var child: Child
        """,
    ])
    func preservesEmission(_ members: String) throws {
        let model = try parse(members)
        let declarations = try DIContainerCodeGenerator.generateAll(for: model)
        let before = declarations.map(\.description)
        try DIContainerCodeGenerator.validateInitialization(for: model)
        #expect(try DIContainerCodeGenerator.generateAll(for: model).map(\.description) == before)
        #expect(declarations.compactMap { $0.as(FunctionDeclSyntax.self) }
            .filter { $0.name.text == "withOverrides" }.count == 4)
    }

    @Test("Explicit DAG opt-out retains recovery fallback")
    func preservesExplicitFallback() throws {
        let model = try parse(
            "@Provide(.shared, factory: { (missing: Int) in missing }) var value: Int",
            attribute: "@DIContainer(validateDAG: false)"
        )
        try DIContainerCodeGenerator.validateInitialization(for: model)
        #expect(try DIContainerCodeGenerator.generateAll(for: model).map(\.description).joined().contains("_innoDITrap"))
    }

    private func parse(_ members: String, attribute: String = "@DIContainer") throws -> DIContainerExpansionModel {
        let source = Parser.parse(source: "\(attribute) struct Container { \(members) }")
        let declaration = try #require(source.statements.first?.item.as(StructDeclSyntax.self))
        return try #require(DIContainerParser.parse(declaration: declaration, context: TestMacroExpansionContext()))
    }

    private func failure(_ operation: () throws -> Void) throws -> String {
        do {
            try operation()
            Issue.record("Invalid model unexpectedly reached emission")
            return ""
        } catch let error as CodegenInvariantError {
            return error.description
        }
    }
}
