import InnoDITestSupport
import SwiftDiagnostics
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

@Suite("Assisted factory prototype")
struct AssistedFactoryPrototypeMacroTests {
    private static let macros: [String: any Macro.Type] =
        DIContainerMacroTests.macros.merging([
            "_InnoDIAssistedFactoryPrototype": InnoDIAssistedFactoryPrototypeMacro.self,
        ]) { current, _ in current }

    @Test("Child-owned factory partitions static and assisted inputs")
    func partitionsStaticAndAssistedInputs() {
        let result = expandMacroSource(
            """
            @_InnoDIAssistedFactoryPrototype(assisted: ["routineID"])
            @DIContainer
            public struct TrainingContainer {
                @Provide(.input) public var repository: any TrainingRepository
                @Provide(.input) public var routineID: Routine.ID
                @Provide(.shared, factory: InstanceToken()) public var token: InstanceToken
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        #expect(result.expansion.contains("public struct _InnoDIAssistedFactoryPrototype"))
        #expect(
            result.expansion.contains(
                "public typealias _InnoDIAssistedFactoryPrototype_TrainingContainer = TrainingContainer._InnoDIAssistedFactoryPrototype"
            )
        )
        #expect(result.expansion.contains("private let repository: any TrainingRepository"))
        #expect(!result.expansion.contains("private let routineID"))
        #expect(result.expansion.contains("public init(repository: any TrainingRepository)"))
        #expect(result.expansion.contains("routineID: Routine.ID"))
        #expect(result.expansion.contains("repository: self.repository"))
        #expect(result.expansion.contains("routineID: routineID"))
    }

    @Test("Main-actor isolation propagates to the child-owned factory")
    func propagatesMainActorIsolation() {
        let result = expandMacroSource(
            """
            @_InnoDIAssistedFactoryPrototype(assisted: ["route"])
            @DIContainer(mainActor: true)
            public struct SceneContainer {
                @Provide(.input) public var service: Service
                @Provide(.input) public var route: Route
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        #expect(
            result.expansion.contains(
                "@_Concurrency.MainActor\n    public struct _InnoDIAssistedFactoryPrototype"
            )
        )
        #expect(
            result.expansion.contains(
                "@_Concurrency.MainActor (inout SceneContainer.Overrides) -> Void"
            )
        )
    }

    @Test("Assisted entries must identify input members")
    func rejectsNonInputAssistedEntry() {
        let result = expandMacroSource(
            """
            @_InnoDIAssistedFactoryPrototype(assisted: ["service"])
            @DIContainer
            struct InvalidContainer {
                @Provide(.shared, factory: Service()) var service: Service
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == [
                MessageID(
                    domain: "InnoDI.experimental",
                    id: "assisted-factory-prototype.unknown-assisted-input"
                ),
            ]
        )
        #expect(!result.expansion.contains("struct _InnoDIAssistedFactoryPrototype"))
        #expect(
            !result.expansion.contains(
                "typealias _InnoDIAssistedFactoryPrototype_InvalidContainer"
            )
        )
    }

    @Test("Assisted entries must be unique plain string literals")
    func rejectsInvalidAssistedLists() {
        let dynamic = expandMacroSource(
            """
            @_InnoDIAssistedFactoryPrototype(assisted: [routeName])
            @DIContainer
            struct DynamicContainer {
                @Provide(.input) var route: Route
            }
            """,
            macros: Self.macros
        )
        let duplicate = expandMacroSource(
            """
            @_InnoDIAssistedFactoryPrototype(assisted: ["route", "route"])
            @DIContainer
            struct DuplicateContainer {
                @Provide(.input) var route: Route
            }
            """,
            macros: Self.macros
        )

        #expect(
            dynamic.diagnostics.map(\.diagnosticID) == [
                MessageID(
                    domain: "InnoDI.experimental",
                    id: "assisted-factory-prototype.invalid-assisted-inputs"
                ),
            ]
        )
        #expect(
            duplicate.diagnostics.map(\.diagnosticID) == [
                MessageID(
                    domain: "InnoDI.experimental",
                    id: "assisted-factory-prototype.duplicate-assisted-input"
                ),
            ]
        )
    }
}
