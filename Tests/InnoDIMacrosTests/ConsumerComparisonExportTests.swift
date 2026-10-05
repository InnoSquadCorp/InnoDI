import Foundation
import InnoDITestSupport
import SwiftBasicFormat
import SwiftParser
import SwiftSyntax
import Testing

@testable import InnoDIMacros

/// Emits actual production macro/accessor output for a capability-matched
/// portable consumer experiment. This is not a Linux package-support claim.
@Suite("Consumer comparison source export")
struct ConsumerComparisonExportTests {
    @Test(.disabled(if: ProcessInfo.processInfo.environment["INNODI_COMPARISON_EXPORT"] == nil))
    func exportConsumer() throws {
        let directory = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["INNODI_COMPARISON_EXPORT"]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let publicSource = Parser.parse(source: try String(contentsOf: root.appendingPathComponent("Sources/InnoDI/InnoDI.swift"), encoding: .utf8))
        let supportDeclarations = publicSource.statements.compactMap { statement -> DeclSyntax? in
            if let function = statement.item.as(FunctionDeclSyntax.self), function.name.text == "_innoDITrap" { return DeclSyntax(function) }
            if let enumeration = statement.item.as(EnumDeclSyntax.self), enumeration.name.text == "DIPrewarmError" { return DeclSyntax(enumeration) }
            return nil
        }
        #expect(supportDeclarations.count == 2)
        try supportDeclarations.map(\.description).joined(separator: "\n")
            .write(to: directory.appendingPathComponent("RuntimeSupport.swift"), atomically: true, encoding: .utf8)
        let members = (0..<20).map { index in
            let arguments = index == 0 ? "counter: Counter" : "counter: Counter, node\(index - 1): Node"
            let parent = index == 0 ? "nil" : "node\(index - 1)"
            return "@Provide(.shared, initialization: .onDemand, factory: { (\(arguments)) in Node(id: \(index), parent: \(parent), counter: counter) }) var node\(index): Node"
        }.joined(separator: "\n")
        let authored = "@DIContainer struct BenchmarkContainer {\n@Input var counter: Counter\n\(members)\n}"
        try authored.write(to: directory.appendingPathComponent("Authored.swift"), atomically: true, encoding: .utf8)
        let syntax = Parser.parse(source: authored)
        let declaration = try #require(syntax.statements.first?.item.as(StructDeclSyntax.self))
        let context = TestMacroExpansionContext()
        let model = try #require(DIContainerParser.parse(declaration: declaration, context: context))
        #expect(DIContainerValidator.validate(model: model, declaration: declaration, context: context))
        let support = Parser.parse(source: "@InnoDI._InnoDIProvideAccessor(recovery: false) var placeholder: Int")
        let attribute = try #require(support.statements.first?.item.as(VariableDeclSyntax.self)?.attributes.first?.as(AttributeSyntax.self))
        var emitted: [DeclSyntax] = []
        for member in declaration.memberBlock.members {
            let variable = try #require(member.decl.as(VariableDeclSyntax.self))
            let peers = try InnoDIProvideAccessorMacro.expansion(of: attribute, providingPeersOf: variable, in: context)
            let accessors = try InnoDIProvideAccessorMacro.expansion(of: attribute, providingAccessorsOf: variable, in: context)
            #expect(!peers.isEmpty && !accessors.isEmpty)
            var property = variable
            property.attributes = AttributeListSyntax([])
            var binding = try #require(property.bindings.first)
            binding.initializer = nil
            binding.accessorBlock = AccessorBlockSyntax(accessors: .accessors(AccessorDeclListSyntax(accessors)))
            property.bindings = PatternBindingListSyntax([binding])
            emitted.append(DeclSyntax(property))
            emitted.append(contentsOf: peers)
        }
        emitted.append(contentsOf: try DIContainerCodeGenerator.generateAll(for: model))
        #expect(context.diagnostics.isEmpty)
        let expanded = "import InnoDI\nstruct BenchmarkContainer {\n\(emitted.map { $0.formatted().description }.joined(separator: "\n"))\n}"
        try expanded.write(to: directory.appendingPathComponent("Expanded.swift"), atomically: true, encoding: .utf8)
    }
}
