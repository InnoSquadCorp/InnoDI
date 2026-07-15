import InnoDITestSupport
import SwiftDiagnostics
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

@Suite("Generated support symbol validation")
struct GeneratedSymbolCollisionTests {
    private static let macros: [String: any Macro.Type] = [
        "DIContainer": DIContainerMacro.self,
        "Provide": ProvideMacro.self,
        "_InnoDIProvideAccessor": InnoDIProvideAccessorMacro.self,
        "InnoDI._InnoDIProvideAccessor": InnoDIProvideAccessorMacro.self,
        "SubContainer": SubContainerMacro.self,
        "_InnoDISubContainerAccessor": InnoDISubContainerAccessorMacro.self,
        "InnoDI._InnoDISubContainerAccessor": InnoDISubContainerAccessorMacro.self,
    ]

    private static let collisionID = MessageID(
        domain: "InnoDI.validation",
        id: "container.generated-symbol-collision"
    )
    private static let duplicateID = MessageID(
        domain: "InnoDI.validation",
        id: "container.duplicate-member-name"
    )

    @Test("Every non-injective generated peer family fails closed")
    func generatedPeerCollisionFamiliesDiagnose() {
        let cases: [
            (
                source: String,
                generatedName: String,
                firstMember: String,
                conflictingMember: String
            )
        ] = [
            (
                """
                @DIContainer
                struct Container {
                    @Provide(.shared, factory: Service(), concrete: true)
                    var task_cache: Service

                    @Provide(.shared, asyncFactory: { () async in Service() }, concrete: true)
                    var cache: Service
                }
                """,
                "_storage_task_cache",
                "task_cache",
                "cache"
            ),
            (
                """
                @DIContainer
                struct Container {
                    @Provide(.input)
                    var sub_feature: Service

                    @SubContainer(scope: .shared, with: [])
                    var feature: Child
                }
                """,
                "_storage_sub_feature",
                "sub_feature",
                "feature"
            ),
            (
                """
                @DIContainer
                struct Container {
                    @Provide(.transient, factory: Service(), concrete: true)
                    var sub_feature: Service

                    @SubContainer(scope: .transient, with: [])
                    var feature: Child
                }
                """,
                "_override_sub_feature",
                "sub_feature",
                "feature"
            ),
            (
                """
                @DIContainer
                struct Container {
                    @Provide(.transient, factory: Service(), concrete: true)
                    var sub_apply_feature: Service

                    @SubContainer(scope: .shared, with: [])
                    var feature: Child
                }
                """,
                "_override_sub_apply_feature",
                "sub_apply_feature",
                "feature"
            ),
            (
                """
                @DIContainer
                struct Container {
                    @SubContainer(scope: .shared, with: [])
                    var apply_feature: Child

                    @SubContainer(scope: .transient, with: [])
                    var feature: Child
                }
                """,
                "_override_sub_apply_feature",
                "apply_feature",
                "feature"
            ),
        ]

        for testCase in cases {
            let result = expandMacroSource(
                testCase.source,
                macros: Self.macros
            )

            #expect(result.diagnostics.map(\.diagnosticID) == [Self.collisionID])
            #expect(
                result.diagnostics.first?.message
                    == "@DIContainer member '\(testCase.conflictingMember)' would generate support symbol '\(testCase.generatedName)', but earlier managed member '\(testCase.firstMember)' already claims it. Rename one of the @Provide or @SubContainer properties."
            )
            #expect(
                result.diagnostics.first?.notes.first?.message
                    == "The first claim for generated support symbol '\(testCase.generatedName)' comes from managed member '\(testCase.firstMember)' here."
            )
            #expect(managedRecoveryAttributeCount(in: result.expansion) == 2)
            #expect(
                !result.expansion.contains(
                    "private let \(testCase.generatedName)"
                )
            )
        }
    }

    @Test("Triple generated claims keep the first source claim")
    func tripleGeneratedPeerCollisionDiagnosesEachLaterClaim() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct Container {
                @Provide(.transient, factory: Service(), concrete: true)
                var sub_apply_feature: Service

                @SubContainer(scope: .shared, with: [])
                var apply_feature: Child

                @SubContainer(scope: .transient, with: [])
                var feature: Child
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == [
                Self.collisionID,
                Self.collisionID,
            ]
        )
        #expect(
            result.diagnostics.allSatisfy {
                $0.notes.first?.message.contains(
                    "managed member 'sub_apply_feature'"
                ) == true
            }
        )
        #expect(managedRecoveryAttributeCount(in: result.expansion) == 3)
        #expect(
            !result.expansion.contains(
                "private let _override_sub_apply_feature"
            )
        )
    }

    @Test("Generated peer collisions remain terminal with MainActor and DAG opt-out")
    func generatedPeerCollisionIgnoresGraphOptOut() {
        let result = expandMacroSource(
            """
            @DIContainer(validateDAG: false, mainActor: true)
            struct Container {
                @Provide(.transient, factory: Service(), concrete: true)
                var sub_feature: Service

                @SubContainer(scope: .transient, with: [])
                var feature: Child

                @Provide(.input)
                var unrelated: Service

                @SubContainer(scope: .shared, with: [])
                var unrelatedChild: Child
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.map(\.diagnosticID) == [Self.collisionID])
        #expect(managedRecoveryAttributeCount(in: result.expansion) == 4)
        #expect(
            result.expansion.components(
                separatedBy: "@Swift.MainActor"
            ).count - 1 == 4
        )
    }

    @Test("Similar generated spellings that occupy different peer slots compile")
    func generatedPeerNearMissesRemainAvailable() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct Container {
                @Provide(.shared, factory: Service(), concrete: true)
                var task_cache: Service

                @Provide(.shared, factory: Service(), concrete: true)
                var cache: Service

                @Provide(.input)
                var sub_feature: Service

                @SubContainer(scope: .transient, with: [])
                var feature: Child

                @Provide(.transient, factory: Service(), concrete: true)
                var apply_other: Service

                @SubContainer(scope: .shared, with: [])
                var other: Child
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        #expect(
            result.expansion.contains("self._storage_task_cache")
        )
        #expect(
            result.expansion.contains("self._storage_cache")
        )
        #expect(
            result.expansion.contains("self._storage_sub_feature")
        )
        #expect(
            result.expansion.contains("self._override_apply_other")
        )
        #expect(
            result.expansion.contains("self._storage_sub_other")
        )
    }

    @Test("Duplicate SubContainer identities use the managed-member diagnostic")
    func duplicateSubContainerNamesFailClosed() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct Container {
                @SubContainer(scope: .shared, with: [])
                var feature: Child

                @SubContainer(scope: .transient, with: [])
                var feature: Child
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.map(\.diagnosticID) == [Self.duplicateID])
        #expect(managedRecoveryAttributeCount(in: result.expansion) == 2)
        #expect(!result.expansion.contains("_storage_sub_feature"))
    }

    @Test("Provide and SubContainer identities share one namespace")
    func duplicateCrossRoleNamesFailClosed() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct Container {
                @Provide(.input)
                var feature: Service

                @SubContainer(scope: .shared, with: [])
                var feature: Child
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.map(\.diagnosticID) == [Self.duplicateID])
        #expect(managedRecoveryAttributeCount(in: result.expansion) == 2)
        #expect(!result.expansion.contains("_storage_feature"))
        #expect(!result.expansion.contains("_storage_sub_feature"))
    }

    @Test("Conditional direct declarations reserve feature-root helpers")
    func conditionalFeatureRootHelperConflictDiagnoses() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct Container {
                #if DEBUG
                func featureRootView() -> ExistingRoot { fatalError() }
                #endif

                @SubContainer(
                    scope: .shared,
                    with: [],
                    featureRoot: FeatureRootScene.self
                )
                var feature: Child
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == [
                MessageID(
                    domain: "InnoDI.validation",
                    id: "swiftui.feature-root-helper-name-conflict"
                )
            ]
        )
        #expect(managedRecoveryAttributeCount(in: result.expansion) == 1)
        #expect(
            result.expansion.components(
                separatedBy: "func featureRootView()"
            ).count - 1 == 1
        )
    }
}

private func managedRecoveryAttributeCount(in expansion: String) -> Int {
    [
        "@InnoDI._InnoDIProvideAccessor(recovery: true)",
        "@InnoDI._InnoDISubContainerAccessor(recovery: true)",
    ].reduce(0) { count, spelling in
        count + expansion.components(separatedBy: spelling).count - 1
    }
}
