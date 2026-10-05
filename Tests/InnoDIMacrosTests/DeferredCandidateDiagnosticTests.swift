import Foundation
import InnoDITestSupport
import SwiftDiagnostics
import SwiftParser
import SwiftSyntax
import Testing

@testable import InnoDIMacros

extension DIContainerMacroTests {
    @Test("Deferred typo candidates follow target eligibility, not declaration order",
          arguments: ["Lazy", "InnoDI.Lazy", "Provider", "InnoDI.Provider"], [false, true])
    func deferredTypoCandidatesAllowTransientTargets(wrapper: String, targetFirst: Bool) throws {
        let target = "@Provide(.transient, factory: Request()) var request: Request"
        let consumer = """
        @Provide(.shared, factory: { (requests: \(wrapper)<Request>) in
            Logger(requests: requests)
        }) var logger: Logger
        """
        let source = """
        @DIContainer struct App {
            \(targetFirst ? target : consumer)
            \(targetFirst ? consumer : target)
        }
        """
        let diagnostic = try deferredCandidateDiagnostic(in: source)
        #expect(diagnostic.fixIts.isEmpty)
        #expect(diagnostic.notes.contains { $0.message.contains("bound uses manually") })
        #expect(diagnostic.notes.contains { $0.message == "Closest injectable member candidate: request." })
        #expect(!diagnostic.notes.contains { $0.message.contains("declaration order") })
    }

    @Test("Lazy typo candidates include forward shared providers and inputs",
          arguments: ["@Provide(.shared, factory: Request())", "@Input"])
    func lazyTypoCandidatesAllowSharedAndInputTargets(declaration: String) throws {
        let diagnostic = try deferredCandidateDiagnostic(in: """
        @DIContainer struct App {
            @Provide(.shared, factory: { (requests: Lazy<Request>) in
                Logger(requests: requests)
            }) var logger: Logger
            \(declaration) var request: Request
        }
        """)
        #expect(diagnostic.fixIts.isEmpty)
        #expect(diagnostic.notes.contains { $0.message.contains("bound uses manually") })
        #expect(!diagnostic.notes.contains { $0.message.contains("declaration order") })
    }

    @Test("Provider typo candidates reject shared and input targets without an order suggestion",
          arguments: ["@Provide(.shared, factory: Request())", "@Input"])
    func providerTypoCandidatesRejectNonTransientTargets(declaration: String) throws {
        let diagnostic = try deferredCandidateDiagnostic(in: """
        @DIContainer struct App {
            \(declaration) var request: Request
            @Provide(.shared, factory: { (requests: Provider<Request>) in
                Logger(requests: requests)
            }) var logger: Logger
        }
        """)
        #expect(diagnostic.fixIts.isEmpty)
        #expect(diagnostic.notes.contains { $0.message.contains("synchronous .transient providers: request") })
        #expect(!diagnostic.notes.contains { $0.message.contains("declaration order") })
    }

    @Test("Deferred typo candidates reject async providers without a rename fix-it",
          arguments: ["Lazy", "Provider"], ["shared", "transient"])
    func deferredTypoCandidatesRejectAsyncTargets(wrapper: String, scope: String) throws {
        let diagnostic = try deferredCandidateDiagnostic(in: """
        @DIContainer struct App {
            @Provide(.\(scope), asyncFactory: { () async in Request() }) var request: Request
            @Provide(.shared, factory: { (requests: \(wrapper)<Request>) in
                Logger(requests: requests)
            }) var logger: Logger
        }
        """)
        #expect(diagnostic.fixIts.isEmpty)
        #expect(diagnostic.notes.contains { $0.message.contains("cannot be injected as \(wrapper)<T>") })
        #expect(!diagnostic.notes.contains { $0.message.contains("declaration order") })
    }

    @Test("Deferred typo candidates preserve ambiguity suppression",
          arguments: ["Lazy", "Provider"])
    func deferredTypoCandidatesDoNotGuessBetweenNames(wrapper: String) throws {
        let diagnostic = try deferredCandidateDiagnostic(in: """
        @DIContainer struct App {
            @Provide(.transient, factory: Request()) var request: Request
            @Provide(.transient, factory: Request()) var request_: Request
            @Provide(.shared, factory: { (requests: \(wrapper)<Request>) in
                Logger(requests: requests)
            }) var logger: Logger
        }
        """)
        #expect(diagnostic.fixIts.isEmpty)
        #expect(diagnostic.notes.contains { $0.message.contains("request, request_") })
    }

    @Test("A unique unused binding fix-it applies and re-expands without errors",
          arguments: ["Int", "Lazy<Int>", "Provider<Int>"])
    func unusedBindingFixItAppliesAndReexpands(type: String) throws {
        let source = """
        @DIContainer struct App {
            @Provide(.transient, factory: 42) var request: Int
            @Provide(.transient, factory: { (requests: \(type)) in 1 }) var value: Int
        }
        """
        let diagnostic = try deferredCandidateDiagnostic(in: source)
        #expect(diagnostic.fixIts.count == 1)
        let fixIt = try #require(diagnostic.fixIts.first)
        #expect(fixIt.changes.count == 1)
        let change = try #require(fixIt.changes.first)
        guard case let .replaceText(range, replacement, _) = change else {
            Issue.record("Parameter fix-it must be one textual replacement")
            return
        }
        var bytes = Array(source.utf8)
        bytes.replaceSubrange(
            range.lowerBound.utf8Offset..<range.upperBound.utf8Offset,
            with: replacement.utf8
        )
        let repaired = String(decoding: bytes, as: UTF8.self)
        #expect(repaired.contains("(request: \(type)) in 1"))
        let parsed = Parser.parse(source: repaired)
        let declaration = try #require(parsed.statements.first?.item.as(StructDeclSyntax.self))
        let attribute = try #require(declaration.attributes.first?.as(AttributeSyntax.self))
        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attribute, providingMembersOf: declaration, in: context)
        #expect(!generated.isEmpty)
        #expect(context.diagnostics.isEmpty)

        // The portable qualification runner sets this output directory, then
        // compiles and executes the source produced by the actual FixIt. A
        // normal unit run still checks the exact edit and clean re-expansion.
        if let path = ProcessInfo.processInfo.environment["INNODI_FIXIT_SOURCE_OUTPUT"] {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let name = type.hasPrefix("Lazy") ? "Lazy" : type.hasPrefix("Provider") ? "Provider" : "Hard"
            let executable = "import InnoDI\n" + repaired + "\n@main struct Check { static func main() { precondition(App().value == 1) } }\n"
            try executable.write(to: directory.appendingPathComponent("Applied\(name)FixIt.swift"), atomically: true, encoding: .utf8)
        }
    }

    @Test("Parameter-only fix-its are suppressed for uses, nested scopes, labels, and capture risks",
          arguments: [
            "requests()",
            "`requests`()",
            "`request`()",
            "{ (`request`: Int) in `request` }(1)",
            "{ requests() }()",
            "{ [requests] in requests() }()",
            "{ (requests: Int) in requests }(1)",
            "Holder(requests: 1).value",
            "Holder().requests",
            "request()",
            "{ (request: Int) in request }(1)",
            "\"value: \\(requests())\".count",
          ])
    func parameterRenameDoesNotRewriteNestedBindings(body: String) throws {
        let diagnostic = try deferredCandidateDiagnostic(in: """
        @DIContainer struct App {
            @Provide(.transient, factory: 42) var request: Int
            @Provide(.transient, factory: { (requests: Provider<Int>) in \(body) }) var value: Int
        }
        """)
        #expect(diagnostic.fixIts.isEmpty)
        #expect(diagnostic.notes.contains { $0.message.contains("bound uses manually") })
    }

    @Test("Escaped parameters and keyword targets never receive token-only rename fixes",
          arguments: [
            "@Input var request: Int; @Provide(.transient, factory: { (`request_`: Int) in request_ }) var value: Int",
            "@Input var `class`: Int; @Provide(.transient, factory: { (clas: Int) in 1 }) var value: Int",
          ])
    func parameterRenameDoesNotRemoveRequiredEscaping(members: String) throws {
        // Expand peer macros too: @Input owns the escaped-property diagnostic,
        // while @DIContainer owns the escaped factory-parameter diagnostic.
        let result = expandMacroSource(
            "@DIContainer struct App { \(members) }",
            macros: [
                "DIContainer": DIContainerMacro.self,
                "Input": ProvideMacro.self,
                "Provide": ProvideMacro.self,
                "_InnoDIProvideAccessor": InnoDIProvideAccessorMacro.self,
            ]
        )
        #expect(result.diagnostics.contains {
            $0.diagnosticID == MessageID(domain: "InnoDI.usage", id: "provide.escaped-identifier-unsupported")
        })
        #expect(result.diagnostics.allSatisfy { $0.fixIts.isEmpty })
    }

    @Test("Deferred typo candidates do not recommend locally invalid providers")
    func deferredTypoCandidatesRejectInvalidConstruction() throws {
        let diagnostic = try deferredCandidateDiagnostic(in: """
        @DIContainer struct App {
            @Provide(.transient, initialization: .onDemand, factory: Request()) var request: Request
            @Provide(.shared, factory: { (requests: Provider<Request>) in
                Logger(requests: requests)
            }) var logger: Logger
        }
        """)
        #expect(diagnostic.fixIts.isEmpty)
        #expect(diagnostic.notes.contains { $0.message.contains("valid synchronous .transient") })
    }
}

private func deferredCandidateDiagnostic(in source: String) throws -> Diagnostic {
    let parsed = Parser.parse(source: source)
    let declaration = try #require(parsed.statements.first?.item.as(StructDeclSyntax.self))
    let attribute = try #require(declaration.attributes.first?.as(AttributeSyntax.self))
    let context = TestMacroExpansionContext()
    let generated = try DIContainerMacro.expansion(of: attribute, providingMembersOf: declaration, in: context)
    #expect(generated.isEmpty)
    return try #require(context.diagnostics.first {
        $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "provide.unresolved-factory-parameter")
    })
}
