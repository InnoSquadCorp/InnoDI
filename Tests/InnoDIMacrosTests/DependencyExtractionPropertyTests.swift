import Testing
import SwiftParser
import SwiftSyntax

import InnoDITestSupport
@testable import InnoDIMacros

@Suite("Dependency Extraction Property Tests")
struct DependencyExtractionPropertyTests {
    @Test("Dependency extraction keeps expected references across factory styles", arguments: Array(0..<200))
    func dependencyExtractionIsStable(seed: Int) throws {
        var rng = SeededRandom(seed: UInt64(seed + 9000))
        let mode = rng.nextInt(upperBound: 3)

        let provideLine: String
        switch mode {
        case 0:
            provideLine = """
            @Provide(.shared, factory: { (config: Config, logger: Logger) in Service(config: config, logger: logger) }, concrete: true)
            var service: Service
            """
        case 1:
            let deps = rng.nextBool() ? "[\\.config, \\.logger]" : "[\\.logger, \\.config]"
            provideLine = """
            @Provide(.shared, Service.self, with: \(deps), concrete: true)
            var service: Service
            """
        default:
            provideLine = """
            @Provide(.shared, concrete: true)
            var service: Service = Service(config: config, logger: logger)
            """
        }

        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var config: Config

            @Provide(.input)
            var logger: Logger

            \(provideLine)
        }
        """

        let file = Parser.parse(source: source)
        guard let decl = file.statements.first?.item.as(StructDeclSyntax.self) else {
            Issue.record("Expected @DIContainer struct.")
            return
        }

        let context = TestMacroExpansionContext()
        let model = DIContainerParser.parse(declaration: decl, context: context)
        let parsedModel = try #require(model)

        let service = try #require(parsedModel.members.first(where: { $0.name == "service" }))
        let dependencies = Set(service.graphDependencyCandidates)
        #expect(dependencies.contains("config"))
        #expect(dependencies.contains("logger"))
    }

    @Test("Dependency extraction ignores string literal tokens while keeping real identifiers", arguments: Array(0..<200))
    func dependencyExtractionIgnoresStringLiteralTokens(seed: Int) throws {
        var rng = SeededRandom(seed: UInt64(seed + 12000))
        let literalTokens = ["logger", "service", "_storage_config", "dependency", "appContainer"]
        let literalToken = literalTokens[rng.nextInt(upperBound: literalTokens.count)]

        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var config: String

            @Provide(.shared, concrete: true)
            var service: Service = Service(text: config + " \(literalToken)")
        }
        """

        let file = Parser.parse(source: source)
        guard let decl = file.statements.first?.item.as(StructDeclSyntax.self) else {
            Issue.record("Expected @DIContainer struct.")
            return
        }

        let context = TestMacroExpansionContext()
        let model = DIContainerParser.parse(declaration: decl, context: context)
        let parsedModel = try #require(model)
        let service = try #require(parsedModel.members.first(where: { $0.name == "service" }))
        let dependencies = Set(service.graphDependencyCandidates)

        #expect(dependencies.contains("config"))
        #expect(!dependencies.contains(literalToken))
    }
}
