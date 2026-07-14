import Testing
import SwiftParser
import SwiftSyntax

import InnoDITestSupport
@testable import InnoDIMacros

@Suite("Explicit Dependency Wiring Property Tests")
struct DependencyExtractionPropertyTests {
    @Test("Explicit wiring keeps expected references across supported factory styles", arguments: Array(0..<200))
    func dependencyExtractionIsStable(seed: Int) throws {
        var rng = SeededRandom(seed: UInt64(seed + 9000))
        let mode = rng.nextInt(upperBound: 2)

        let provideLine: String
        switch mode {
        case 0:
            provideLine = """
            @Provide(.shared, factory: { (config: Config, logger: Logger) in Service(config: config, logger: logger) }, concrete: true)
            var service: Service
            """
        case 1:
            let deps = rng.nextBool()
                ? "[\\Self.config, \\Self.logger]"
                : "[\\Self.logger, \\Self.config]"
            provideLine = """
            @Provide(.shared, Service.self, with: \(deps), concrete: true)
            var service: Service
            """
        default:
            Issue.record("Unexpected explicit wiring mode")
            return
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

    @Test("Opaque property initializers do not create DI graph edges", arguments: Array(0..<200))
    func opaqueInitializersDoNotCreateDependencyEdges(seed: Int) throws {
        var rng = SeededRandom(seed: UInt64(seed + 12000))
        let literalTokens = ["logger", "service", "_storage_config", "dependency", "appContainer"]
        let literalToken = literalTokens[rng.nextInt(upperBound: literalTokens.count)]

        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.shared, concrete: true)
            var service: Service = Service(text: "\(literalToken)")
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

        #expect(dependencies.isEmpty)
    }

    @Test(
        "Dependency extraction is stable under whitespace and comment perturbations",
        arguments: Array(0..<200)
    )
    func dependencyExtractionIsStableUnderWhitespaceVariations(seed: Int) throws {
        var rng = SeededRandom(seed: UInt64(seed + 15000))

        // 문법상 안전한 위치에 가변 trivia를 주입한다. `ws()`가 반환하는 공백/주석
        // 시퀀스는 토큰 경계에서만 삽입되므로 파서가 동일한 식별자 토큰을 얻어야 한다.
        func ws() -> String { rng.nextWhitespace() }

        let factoryStyle = rng.nextChoice(["closure", "with"])
        let provideLine: String
        switch factoryStyle {
        case "closure":
            provideLine = """
            @Provide(.shared,\(ws())factory:\(ws()){ (config:\(ws())Config,\(ws())logger:\(ws())Logger) in\(ws())Service(config:\(ws())config,\(ws())logger:\(ws())logger) },\(ws())concrete:\(ws())true)
            var service: Service
            """
        case "with":
            let deps = rng.nextChoice([
                "[\\Self.config,\(ws())\\Self.logger]",
                "[\(ws())\\Self.logger,\(ws())\\Self.config\(ws())]"
            ])
            provideLine = """
            @Provide(.shared,\(ws())Service.self,\(ws())with:\(ws())\(deps),\(ws())concrete:\(ws())true)
            var service: Service
            """
        default:
            Issue.record("Unexpected explicit wiring style")
            return
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
            Issue.record("Expected @DIContainer struct. Source was: \(source)")
            return
        }

        let context = TestMacroExpansionContext()
        guard let parsedModel = DIContainerParser.parse(declaration: decl, context: context) else {
            Issue.record("DIContainerParser returned nil. Source was: \(source)")
            return
        }

        guard let service = parsedModel.members.first(where: { $0.name == "service" }) else {
            Issue.record("Expected service member. Source was: \(source)")
            return
        }

        let dependencies = Set(service.graphDependencyCandidates)
        #expect(dependencies.contains("config"), "config not found (style=\(factoryStyle)) in: \(source)")
        #expect(dependencies.contains("logger"), "logger not found (style=\(factoryStyle)) in: \(source)")
    }
}
