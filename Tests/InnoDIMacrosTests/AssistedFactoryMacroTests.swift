import InnoDITestSupport
import SwiftDiagnostics
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

@Suite("Assisted factory")
struct AssistedFactoryMacroTests {
    private static let macros: [String: any Macro.Type] =
        DIContainerMacroTests.macros.merging([
            "AssistedFactory": AssistedFactoryMacro.self,
            "SubContainerFactory": ProvideMacro.self,
            "_InnoDIAssistedFactoryMetadata": InnoDIAssistedFactoryMetadataMacro.self,
            "InnoDI._InnoDIAssistedFactoryMetadata": InnoDIAssistedFactoryMetadataMacro.self,
        ]) { _, new in new }

    @Test("factory owns static inputs and accepts assisted inputs")
    func expandsTypedFactoryMembers() {
        let result = expandMacroSource(
            """
            @_InnoDIAssistedFactoryMetadata(
                order: ["repository", "sessionID"],
                escaping: [],
                mainActor: false
            )
            @AssistedFactory(
                Child.self,
                static: [\\Child.repository],
                assisted: [\\Child.sessionID]
            )
            public struct AssistedFactory {}
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        #expect(result.expansion.contains("private let repository: Child._InnoDIInputType_repository"))
        #expect(result.expansion.contains("public init(repository: Child._InnoDIInputType_repository)"))
        #expect(result.expansion.contains("sessionID: Child._InnoDIInputType_sessionID"))
        #expect(result.expansion.contains("repository: self.repository"))
        #expect(result.expansion.contains("sessionID: sessionID"))
    }

    @Test("main-actor child factory preserves override closure isolation")
    func preservesMainActorOverrideIsolation() {
        let result = expandMacroSource(
            """
            @DIContainer(mainActor: true)
            struct Child {
                @Input var repository: Repository
                @Input(.assisted) var sessionID: Int

                @_InnoDIAssistedFactoryMetadata(
                    order: ["repository", "sessionID"],
                    escaping: [],
                    mainActor: true
                )
                @AssistedFactory(
                    Child.self,
                    static: [\\Child.repository],
                    assisted: [\\Child.sessionID]
                )
                struct AssistedFactory {}
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        #expect(
            result.expansion.contains(
                "_ _innoDIApplyOverrides: @_Concurrency.MainActor (inout Child.Overrides) -> Void"
            )
        )
        #expect(result.expansion.contains("@_Concurrency.MainActor init(repository:"))
        #expect(result.expansion.contains("@_Concurrency.MainActor func callAsFunction("))
    }

    @Test("child declaration order controls forwarded initializer arguments")
    func preservesChildInputDeclarationOrder() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct Child {
                @Input(.assisted) var sessionID: Int
                @Input var repository: Repository

                @_InnoDIAssistedFactoryMetadata(
                    order: ["sessionID", "repository"],
                    escaping: [],
                    mainActor: false
                )
                @AssistedFactory(
                    Child.self,
                    static: [\\Child.repository],
                    assisted: [\\Child.sessionID]
                )
                struct AssistedFactory {}
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        let sessionID = result.expansion.range(of: "sessionID: sessionID")
        let repository = result.expansion.range(of: "repository: self.repository")
        #expect(sessionID != nil)
        #expect(repository != nil)
        if let sessionID, let repository {
            #expect(sessionID.lowerBound < repository.lowerBound)
        }
    }

    @Test("factory parameters preserve escaping input contracts")
    func preservesEscapingInputContracts() {
        let result = expandMacroSource(
            """
            typealias Handler = () -> Void

            @DIContainer
            struct Child {
                @Input(.assisted) var completion: () -> Void
                @Input(escaping: true) var callback: Handler

                @_InnoDIAssistedFactoryMetadata(
                    order: ["completion", "callback"],
                    escaping: ["completion", "callback"],
                    mainActor: false
                )
                @AssistedFactory(
                    Child.self,
                    static: [\\Child.callback],
                    assisted: [\\Child.completion]
                )
                struct AssistedFactory {}
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        #expect(
            result.expansion.contains(
                "init(callback: @escaping Child._InnoDIInputType_callback)"
            )
        )
        #expect(
            result.expansion.contains(
                "completion: @escaping Child._InnoDIInputType_completion"
            )
        )
    }

    @Test("factory key paths must be rooted in the declared child")
    func rejectsUnrelatedKeyPathRoots() {
        let result = expandMacroSource(
            """
            struct Unrelated {
                var repository: Repository
                var sessionID: Int
            }

            @DIContainer
            struct Child {
                @Input var repository: Repository
                @Input(.assisted) var sessionID: Int

                @AssistedFactory(
                    Child.self,
                    static: [\\Unrelated.repository],
                    assisted: [\\Unrelated.sessionID]
                )
                struct AssistedFactory {}
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID).contains(
                MessageID(
                    domain: "InnoDI.usage",
                    id: "assisted-factory.invalid-arguments"
                )
            )
        )
    }

    @Test("factory key paths must name direct child inputs")
    func rejectsChainedKeyPaths() {
        let result = expandMacroSource(
            """
            @AssistedFactory(
                Child.self,
                static: [\\Child.repository.service],
                assisted: [\\Child.sessionID]
            )
            struct AssistedFactory {}
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID).contains(
                MessageID(
                    domain: "InnoDI.usage",
                    id: "assisted-factory.invalid-arguments"
                )
            )
        )
    }

    @Test("factory access cannot exceed its child input bridge")
    func rejectsBroaderFactoryAccess() {
        let result = expandMacroSource(
            """
            @DIContainer
            public struct Child {
                @Input var repository: Repository
                @Input(.assisted) var sessionID: Int

                @AssistedFactory(
                    Child.self,
                    static: [\\Child.repository],
                    assisted: [\\Child.sessionID]
                )
                public struct AssistedFactory {}
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID).contains(
                MessageID(
                    domain: "InnoDI.validation",
                    id: "assisted-factory.access-level-mismatch"
                )
            )
        )
    }

    @Test("package factory accepts package-visible input bridges")
    func acceptsPackageFactoryAccess() {
        let result = expandMacroSource(
            """
            @DIContainer
            package struct Child {
                @Input package var repository: Repository
                @Input(.assisted) package var sessionID: Int

                @AssistedFactory(
                    Child.self,
                    static: [\\Child.repository],
                    assisted: [\\Child.sessionID]
                )
                package struct AssistedFactory {}
            }
            """,
            macros: Self.macros
        )

        #expect(
            !result.diagnostics.map(\.diagnosticID).contains(
                MessageID(
                    domain: "InnoDI.validation",
                    id: "assisted-factory.access-level-mismatch"
                )
            )
        )
    }

    @Test("factory input partition must match the child declaration")
    func rejectsMismatchedPartition() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct Child {
                @Input var repository: Repository
                @Input(.assisted) var sessionID: Int

                @AssistedFactory(
                    Child.self,
                    static: [\\Child.sessionID],
                    assisted: [\\Child.repository]
                )
                struct AssistedFactory {}
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID).contains(
                MessageID(
                    domain: "InnoDI.validation",
                    id: "assisted-factory.input-partition-mismatch"
                )
            )
        )
    }

    @Test("input-derived factory generation is deterministic")
    func inputDerivedGenerationIsDeterministic() {
        let source = """
            typealias Callback = () -> Void

            @DIContainer
            struct Child {
                @Input var repository: Repository
                @Input(escaping: true) var callback: Callback
                @Input(.assisted) var itemID: Int

                @AssistedFactory(
                    Child.self,
                    static: [\\Child.repository, \\Child.callback],
                    assisted: [\\Child.itemID]
                )
                struct AssistedFactory {}
            }
            """

        let first = expandMacroSource(source, macros: Self.macros)
        let second = expandMacroSource(source, macros: Self.macros)

        #expect(first.diagnostics.isEmpty)
        #expect(first.expansion == second.expansion)
        #expect(first.expansion.contains("_InnoDIInputType_repository"))
        #expect(first.expansion.contains("_InnoDIInputType_callback"))
        #expect(first.expansion.contains("_InnoDIInputType_itemID"))
        #expect(first.expansion.contains("callback: @escaping"))
        #expect(first.expansion.contains("itemID:"))
    }

    @Test(
        "input edits make stale key-path partitions fail closed",
        arguments: [
            "@Input var added: Int\n@Input(.assisted) var itemID: Int",
            "@Input(.assisted) var renamedItemID: Int",
            "@Input(.assisted) var itemID: Int",
        ]
    )
    func staleInputEditsAreRejected(editedInput: String) {
        let source = """
            @DIContainer
            struct Child {
                @Input var repository: Repository
                \(editedInput)

                @AssistedFactory(
                    Child.self,
                    static: [\\Child.repository, \\Child.removed],
                    assisted: [\\Child.itemID]
                )
                struct AssistedFactory {}
            }
            """
        let result = expandMacroSource(source, macros: Self.macros)

        #expect(
            result.diagnostics.map(\.diagnosticID).contains(
                MessageID(
                    domain: "InnoDI.validation",
                    id: "assisted-factory.input-partition-mismatch"
                )
            )
        )
    }
}
