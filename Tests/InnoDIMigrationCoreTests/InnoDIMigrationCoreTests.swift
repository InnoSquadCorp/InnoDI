import Foundation
import InnoDITestSupport
@testable import InnoDIMigrationCore
import Testing

@Suite("InnoDI migration", .serialized)
struct InnoDIMigrationCoreTests {
    @Test("CLI requires one root and one mode")
    func argumentContract() {
        #expect(parseMigrationArguments([]) == .failure(.missingRoot))
        #expect(
            parseMigrationArguments(["--root", "/tmp/package"])
                == .failure(.missingMode)
        )
        #expect(
            parseMigrationArguments(["--root", "/tmp/package", "--check", "--write"])
                == .failure(.mutuallyExclusiveModes)
        )
        #expect(
            parseMigrationArguments(["--root", "/tmp/package", "--check"])
                == .options(MigrationOptions(rootPath: "/tmp/package", mode: .check))
        )
        #expect(
            parseMigrationArguments([
                "--root", "/tmp/package", "--report", "--output", "migration.json",
            ])
                == .options(
                    MigrationOptions(
                        rootPath: "/tmp/package",
                        mode: .report,
                        outputPath: "migration.json"
                    )
                )
        )
        #expect(
            parseMigrationArguments([
                "--root", "/tmp/package", "--check", "--output", "migration.json",
            ])
                == .failure(.outputRequiresReport)
        )
        #expect(
            parseMigrationArguments(["--root", "/tmp/package", "--report", "--write"])
                == .failure(.mutuallyExclusiveModes)
        )
        #expect(
            parseMigrationArguments(["--root", "/tmp/package", "--check", "--check"])
                == .failure(.duplicateOption("--check"))
        )
        #expect(
            parseMigrationArguments(["--root"])
                == .failure(.missingOptionValue("--root"))
        )
        #expect(
            parseMigrationArguments(["--root", "", "--write"])
                == .failure(.missingOptionValue("--root"))
        )
        #expect(
            parseMigrationArguments(["--root", "/tmp/package", "--unknown"])
                == .failure(.unknownOption("--unknown"))
        )
    }

    @Test("CLI argument failures provide actionable descriptions")
    func argumentErrorDescriptions() {
        #expect(
            MigrationArgumentError.duplicateOption("--report").description
                == "Option may be specified only once: --report"
        )
        #expect(
            MigrationArgumentError.missingOptionValue("--output").description
                == "Missing value for option: --output"
        )
        #expect(MigrationArgumentError.missingRoot.description == "--root <path> is required.")
        #expect(
            MigrationArgumentError.missingMode.description
                == "Exactly one of --check, --report, or --write is required."
        )
        #expect(
            MigrationArgumentError.mutuallyExclusiveModes.description
                == "--check, --report, and --write are mutually exclusive."
        )
        #expect(
            MigrationArgumentError.outputRequiresReport.description
                == "--output may be used only with --report."
        )
        #expect(
            MigrationArgumentError.unexpectedArgument("Sources").description
                == "Unexpected positional argument: Sources"
        )
        #expect(
            MigrationArgumentError.unknownOption("--json").description
                == "Unknown option: --json"
        )
    }

    @Test("Structured reports are deterministic and omit source bodies")
    func structuredReportIsDeterministicAndSourceFree() throws {
        let plan = MigrationPlan(
            scannedFileCount: 3,
            changes: [
                MigrationFileChange(
                    path: "Sources/Z.swift",
                    originalSource: "private-original-z",
                    migratedSource: "private-migrated-z"
                ),
                MigrationFileChange(
                    path: "Sources/A.swift",
                    originalSource: "private-original-a",
                    migratedSource: "private-migrated-a"
                ),
            ],
            diagnostics: []
        )
        let report = MigrationReport(plan: plan)

        #expect(report.schemaVersion == 1)
        #expect(report.status == .changesRequired)
        #expect(report.changeCount == 2)
        #expect(report.diagnosticCount == 0)
        #expect(report.changes.map(\.path) == ["Sources/A.swift", "Sources/Z.swift"])
        #expect(report.exitCode == 1)

        let first = try report.encodedJSON()
        let second = try report.encodedJSON()
        #expect(first == second)
        let rendered = String(decoding: first, as: UTF8.self)
        #expect(!rendered.contains("private-original"))
        #expect(!rendered.contains("private-migrated"))
        #expect(try JSONDecoder().decode(MigrationReport.self, from: first) == report)
    }

    @Test("Structured reports classify diagnostics as blocked")
    func structuredReportClassifiesDiagnosticsAsBlocked() {
        let report = MigrationReport(
            plan: MigrationPlan(
                scannedFileCount: 1,
                changes: [],
                diagnostics: [
                    MigrationDiagnostic(
                        code: "migrate.parse-error",
                        path: "Broken.swift",
                        message: "Invalid syntax."
                    ),
                ]
            )
        )

        #expect(report.status == .blocked)
        #expect(report.exitCode == 2)
        #expect(report.diagnostics.map(\.path) == ["Broken.swift"])
    }

    @Test("Structured reports classify an unchanged tree as clean")
    func structuredReportClassifiesCleanTree() {
        let report = MigrationReport(
            plan: MigrationPlan(
                scannedFileCount: 4,
                changes: [],
                diagnostics: []
            )
        )

        #expect(report.status == .clean)
        #expect(report.exitCode == 0)
        #expect(!report.requiresChanges)
        #expect(report.canWrite)
    }

    @Test("6.0 input, role, and isolation rewrites are idempotent")
    func migratesSixDotZeroVocabularyIdempotently() throws {
        let root = try makeTemporaryTree(files: [
            "Sources/App.swift": """
            import InnoDI

            @DIComponent
            @DIContainer(mainActor: true, validateDAG: false)
            struct FeatureContainer {
                @Provide(.input) var config: Config
                @InnoDI.Provide(InnoDI.DIScope.input, escaping: true)
                var callback: Callback
            }

            @DIHierarchyRoot
            @DIContainer(root: true)
            struct AppContainer {}

            @InnoDI.DIComponent
            @InnoDI.DIContainer(mainActor: true)
            struct QualifiedFeatureContainer {}
            """,
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let migrator = InnoDIMigrator()
        let plan = try migrator.plan(root: root)
        #expect(plan.diagnostics.isEmpty)
        let migrated = try #require(plan.changes.first?.migratedSource)
        #expect(
            migrated.contains(
                "@DIContainerRole(ContainerRole.component, isolation: DIContainerIsolation.mainActor, validateDAG: false)"
            )
        )
        #expect(migrated.contains("@Input var config"))
        #expect(migrated.contains("@InnoDI.Input(escaping: true)"))
        #expect(migrated.contains("@DIContainerRole(ContainerRole.root)"))
        #expect(
            migrated.contains(
                "@InnoDI.DIContainerRole(InnoDI.ContainerRole.component, isolation: InnoDI.DIContainerIsolation.mainActor)"
            )
        )
        #expect(!migrated.contains("@DIComponent"))
        #expect(!migrated.contains("@DIHierarchyRoot"))
        #expect(!migrated.contains("@Provide(.input)"))

        _ = try migrator.run(root: root, mode: .write)
        let second = try migrator.plan(root: root)
        #expect(second.diagnostics.isEmpty)
        #expect(second.changes.isEmpty)
    }

    @Test("Concrete and stacked feature-root surfaces migrate idempotently")
    func migratesConcreteAndFeatureRootsIdempotently() throws {
        let root = try makeTemporaryTree(files: [
            "Sources/App/App.swift": """
            import InnoDISwiftUI

            struct Service {}
            struct ChildContainer {}
            struct DashboardRootView {}
            struct DashboardShellView {}

            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: Service(), concrete: true)
                var service: Service

                @SubContainer(scope: .shared)
                @DIFeatureRoot(DashboardRootView.self)
                @InnoDISwiftUI.DIFeatureRoot(DashboardShellView.self, as: "dashboardShell")
                var dashboard: ChildContainer
            }
            """,
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let migrator = InnoDIMigrator()
        let plan = try migrator.plan(root: root)
        #expect(plan.diagnostics.isEmpty)
        #expect(plan.changes.map(\.path) == ["Sources/App/App.swift"])

        let migrated = try #require(plan.changes.first?.migratedSource)
        #expect(!migrated.contains("concrete:"))
        #expect(!migrated.contains(", )"))
        #expect(!migrated.contains("DIFeatureRoot"))
        #expect(migrated.contains("featureRoots:"))
        #expect(migrated.contains("InnoDI.FeatureRoot(DashboardRootView.self)"))
        #expect(
            migrated.contains(
                "InnoDI.FeatureRoot(DashboardShellView.self, as: \"dashboardShell\")"
            )
        )

        let writePlan = try migrator.run(root: root, mode: .write)
        #expect(writePlan.changes.count == 1)
        let secondPlan = try migrator.plan(root: root)
        #expect(secondPlan.diagnostics.isEmpty)
        #expect(secondPlan.changes.isEmpty)
    }

    @Test("One default feature root uses the short featureRoot form")
    func singleFeatureRootUsesShortForm() throws {
        let root = try makeTemporaryTree(files: [
            "Feature.swift": """
            import InnoDISwiftUI

            @InnoDI.SubContainer(scope: .transient)
            @InnoDISwiftUI.DIFeatureRoot(FeatureView.self)
            var feature: FeatureContainer
            """,
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = try InnoDIMigrator().plan(root: root)
        let migrated = try #require(plan.changes.first?.migratedSource)
        #expect(plan.diagnostics.isEmpty)
        #expect(migrated.contains("featureRoot: FeatureView.self"))
        #expect(!migrated.contains("featureRoots:"))
        #expect(!migrated.contains("DIFeatureRoot"))
    }

    @Test("Foreign qualified macros are preserved")
    func foreignQualifiedMacrosArePreserved() throws {
        let source = """
        import InnoDI

        @OtherDI.Provide(.shared, factory: Service(), concrete: true)
        var service: Service

        @OtherDI.SubContainer(scope: .shared)
        @OtherDI.DIFeatureRoot(FeatureView.self)
        var feature: FeatureContainer
        """
        let root = try makeTemporaryTree(files: ["Foreign.swift": source])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = try InnoDIMigrator().plan(root: root)
        #expect(plan.diagnostics.isEmpty)
        #expect(plan.changes.isEmpty)
        #expect(try String(contentsOf: root.appendingPathComponent("Foreign.swift"), encoding: .utf8) == source)
    }

    @Test("Unqualified legacy-looking macros without a proven owner block migration")
    func unqualifiedLookalikesWithoutImportBlockMigration() throws {
        let source = """
        import OtherDI

        @Provide(.shared, factory: Service(), concrete: true)
        var service: Service
        """
        let root = try makeTemporaryTree(files: ["Lookalike.swift": source])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = try InnoDIMigrator().plan(root: root)
        #expect(plan.changes.isEmpty)
        #expect(plan.diagnostics.map(\.code) == ["migrate.unqualified-ownership-ambiguous"])
    }

    @Test("A second macro namespace blocks unqualified migration")
    func untrustedMacroNamespaceBlocksUnqualifiedMigration() throws {
        let source = """
        import InnoDI
        import OtherDI

        @DIContainer
        struct Container {
            @Provide(.shared, factory: Service(), concrete: true)
            var service: Service
        }
        """
        let root = try makeTemporaryTree(files: ["Ambiguous.swift": source])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = try InnoDIMigrator().run(root: root, mode: .write)
        #expect(plan.changes.isEmpty)
        #expect(plan.diagnostics.map(\.code) == ["migrate.unqualified-ownership-ambiguous"])
        #expect(
            try String(contentsOf: root.appendingPathComponent("Ambiguous.swift"), encoding: .utf8)
                == source
        )
    }

    @Test("Exported untrusted macro namespaces block sibling-file migration")
    func exportedUntrustedNamespaceBlocksSiblingMigration() throws {
        let root = try makeTemporaryTree(files: [
            "Exports.swift": "@_exported import OtherDI",
            "Consumer.swift": """
            import InnoDI

            @DIContainer
            struct Container {
                @Provide(.shared, factory: Service(), concrete: true)
                var service: Service
            }
            """,
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = try InnoDIMigrator().run(root: root, mode: .write)
        #expect(plan.changes.isEmpty)
        #expect(plan.diagnostics.map(\.code) == ["migrate.unqualified-ownership-ambiguous"])
    }

    @Test("A selectively imported non-macro declaration does not block migration")
    func selectiveNonMacroImportAllowsMigration() throws {
        let source = """
        import InnoDI
        import struct OtherModule.Service

        @DIContainer
        struct Container {
            @Provide(.shared, factory: Service(), concrete: true)
            var service: Service
        }
        """
        let root = try makeTemporaryTree(files: ["Selective.swift": source])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = try InnoDIMigrator().plan(root: root)
        #expect(plan.diagnostics.isEmpty)
        let migrated = try #require(plan.changes.first?.migratedSource)
        #expect(!migrated.contains("concrete:"))
    }

    @Test("A local Provide type does not hide the InnoDI macro namespace")
    func localProvideTypeDoesNotHideMacro() throws {
        let source = """
        import InnoDI

        @propertyWrapper
        struct Provide<Value> {
            var wrappedValue: Value
            init(wrappedValue: Value, concrete: Bool) {
                self.wrappedValue = wrappedValue
            }
        }

        @InnoDI.DIContainer
        struct Container {
            @Provide(concrete: true)
            var service = Service()
        }
        """
        let root = try makeTemporaryTree(files: ["Shadow.swift": source])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = try InnoDIMigrator().plan(root: root)
        #expect(plan.diagnostics.isEmpty)
        let migrated = try #require(plan.changes.first?.migratedSource)
        #expect(migrated.contains("init(wrappedValue: Value, concrete: Bool)"))
        #expect(migrated.contains("@Provide()"))
        #expect(!migrated.contains("@Provide(concrete:"))
    }

    @Test("A package-local macro name blocks unqualified migration")
    func localMacroShadowBlocksMigration() throws {
        let root = try makeTemporaryTree(files: [
            "Sources/Macro.swift": """
            @attached(peer)
            macro Provide(
                _ scope: Any? = nil,
                factory: Any? = nil,
                concrete: Bool = false
            ) = #externalMacro(module: "LocalMacros", type: "ProvideMacro")
            """,
            "Sources/Consumer.swift": """
            import InnoDI

            @DIContainer
            struct Container {
                @Provide(.shared, factory: Service(), concrete: true)
                var service: Service
            }
            """,
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = try InnoDIMigrator().run(root: root, mode: .write)
        #expect(plan.changes.isEmpty)
        #expect(plan.diagnostics.map(\.code) == ["migrate.unqualified-ownership-ambiguous"])
    }

    @Test("Package-root macro shadows conservatively block every unqualified target")
    func macroShadowsArePackageWide() throws {
        let root = try makeTemporaryTree(files: [
            "Sources/LocalMacros/Provide.swift": """
            @attached(peer)
            macro Provide(
                _ scope: Any? = nil,
                factory: Any? = nil,
                concrete: Bool = false
            ) = #externalMacro(module: "LocalMacrosPlugin", type: "ProvideMacro")
            """,
            "Sources/App/App.swift": """
            import InnoDI

            @DIContainer
            struct Container {
                @Provide(.shared, factory: Service(), concrete: true)
                var service: Service
            }
            """,
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = try InnoDIMigrator().plan(root: root)
        #expect(plan.changes.isEmpty)
        #expect(plan.diagnostics.map(\.code) == ["migrate.unqualified-ownership-ambiguous"])
    }

    @Test("Escaped macro declarations participate in package-wide ownership")
    func escapedMacroShadowBlocksMigration() throws {
        let root = try makeTemporaryTree(files: [
            "Macro.swift": """
            @attached(peer)
            macro `Provide`(
                _ scope: Any? = nil,
                factory: Any? = nil,
                concrete: Bool = false
            ) = #externalMacro(module: "LocalMacros", type: "ProvideMacro")
            """,
            "Consumer.swift": """
            import InnoDI

            @DIContainer
            struct Container {
                @Provide(.shared, factory: Service(), concrete: true)
                var service: Service
            }
            """,
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = try InnoDIMigrator().run(root: root, mode: .write)
        #expect(plan.changes.isEmpty)
        #expect(plan.diagnostics.map(\.code) == ["migrate.unqualified-ownership-ambiguous"])
    }

    @Test("Escaped InnoDI attributes and a false concrete argument migrate")
    func escapedLegacyIdentifiersMigrate() throws {
        let source = """
        import InnoDI

        @`DIContainer`
        struct Container {
            @`Provide`(.shared, factory: Service(), `concrete`: false)
            var service: Service
        }
        """
        let root = try makeTemporaryTree(files: ["Escaped.swift": source])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = try InnoDIMigrator().plan(root: root)
        #expect(plan.diagnostics.isEmpty)
        let migrated = try #require(plan.changes.first?.migratedSource)
        #expect(!migrated.contains("concrete"))
    }

    @Test("Conditional imports make unqualified ownership ambiguous")
    func conditionalImportBlocksUnqualifiedMigration() throws {
        let source = """
        #if canImport(InnoDI)
        import InnoDI
        #endif

        @DIContainer
        struct Container {
            @Provide(.shared, factory: Service(), concrete: true)
            var service: Service
        }
        """
        let root = try makeTemporaryTree(files: ["Conditional.swift": source])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = try InnoDIMigrator().plan(root: root)
        #expect(plan.changes.isEmpty)
        #expect(plan.diagnostics.map(\.code) == ["migrate.unqualified-ownership-ambiguous"])
    }

    @Test("Qualified macros migrate across conditional imports")
    func qualifiedMacrosMigrateAcrossConditionalImports() throws {
        let source = """
        #if canImport(InnoDI)
        import InnoDI
        #endif

        @InnoDI.DIContainer
        struct Container {
            @InnoDI.Provide(.shared, factory: Service(), concrete: true)
            var service: Service
        }
        """
        let root = try makeTemporaryTree(files: ["Conditional.swift": source])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = try InnoDIMigrator().plan(root: root)
        let migrated = try #require(plan.changes.first?.migratedSource)
        #expect(plan.diagnostics.isEmpty)
        #expect(!migrated.contains("concrete:"))
    }

    @Test("Conditional container members migrate without leaving concrete arguments")
    func conditionalContainerMembersMigrate() throws {
        let source = """
        import InnoDI

        @DIContainer
        struct Container {
            #if FEATURE_ENABLED
            @Provide(.shared, factory: Service(), concrete: true)
            var service: Service
            #endif
        }
        """
        let root = try makeTemporaryTree(files: ["ConditionalMember.swift": source])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = try InnoDIMigrator().plan(root: root)
        #expect(plan.diagnostics.isEmpty)
        let migrated = try #require(plan.changes.first?.migratedSource)
        #expect(!migrated.contains("concrete:"))
    }

    @Test("Owned concrete arguments outside supported placement block migration")
    func unsupportedConcretePlacementBlocksMigration() throws {
        let source = """
        import InnoDI

        @Provide(.shared, factory: Service(), concrete: true)
        var service: Service
        """
        let root = try makeTemporaryTree(files: ["Unsupported.swift": source])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = try InnoDIMigrator().run(root: root, mode: .write)
        #expect(plan.changes.isEmpty)
        #expect(plan.diagnostics.map(\.code) == ["migrate.concrete-placement-ambiguous"])
        #expect(
            try String(contentsOf: root.appendingPathComponent("Unsupported.swift"), encoding: .utf8)
                == source
        )
    }

    @Test("Declaration-macro payloads are never rewritten")
    func declarationMacroPayloadBlocksMigration() throws {
        let source = """
        import InnoDISwiftUI

        @DIContainer
        struct Container {
            #declarations {
                @Provide(.shared, factory: Service(), concrete: true)
                var service: Service

                @SubContainer(scope: .shared)
                @DIFeatureRoot(FeatureView.self)
                var feature: FeatureContainer
            }
        }
        """
        let root = try makeTemporaryTree(files: ["MacroPayload.swift": source])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = try InnoDIMigrator().run(root: root, mode: .write)
        #expect(plan.changes.isEmpty)
        #expect(
            plan.diagnostics.map(\.code) == [
                "migrate.concrete-placement-ambiguous",
                "migrate.feature-root-ambiguous",
            ]
        )
        #expect(
            try String(contentsOf: root.appendingPathComponent("MacroPayload.swift"), encoding: .utf8)
                == source
        )
    }

    @Test("Expression-macro payloads are never rewritten")
    func expressionMacroPayloadBlocksMigration() throws {
        let source = """
        import InnoDI

        let payload = #expressionMacro {
            @DIContainer
            struct Container {
                @Provide(.shared, factory: Service(), concrete: true)
                var service: Service
            }
        }
        """
        let root = try makeTemporaryTree(files: ["ExpressionPayload.swift": source])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = try InnoDIMigrator().run(root: root, mode: .write)
        #expect(plan.changes.isEmpty)
        #expect(plan.diagnostics.map(\.code) == ["migrate.concrete-placement-ambiguous"])
        #expect(
            try String(contentsOf: root.appendingPathComponent("ExpressionPayload.swift"), encoding: .utf8)
                == source
        )
    }

    @Test("Unsupported concrete arguments block every write")
    func unsupportedConcreteArgumentBlocksEveryWrite() throws {
        let safeSource = """
        import InnoDI
        @DIContainer
        struct SafeContainer {
            @Provide(.shared, factory: Service(), concrete: true)
            var service: Service
        }
        """
        let blockedSource = """
        import InnoDI
        @DIContainer
        struct BlockedContainer {
            @Provide(.shared, factory: Service(), concrete: featureFlags.useConcrete)
            var service: Service
        }
        """
        let root = try makeTemporaryTree(files: [
            "Safe.swift": safeSource,
            "Blocked.swift": blockedSource,
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = try InnoDIMigrator().run(root: root, mode: .write)
        #expect(plan.changes.map(\.path) == ["Safe.swift"])
        #expect(plan.diagnostics.map(\.code) == ["migrate.concrete-argument-unsupported"])
        #expect(!plan.canWrite)
        #expect(
            try String(contentsOf: root.appendingPathComponent("Safe.swift"), encoding: .utf8)
                == safeSource
        )
        #expect(
            try String(contentsOf: root.appendingPathComponent("Blocked.swift"), encoding: .utf8)
                == blockedSource
        )
    }

    @Test("Comments on concrete arguments block migration")
    func concreteCommentBlocksMigration() throws {
        let source = """
        import InnoDI
        @DIContainer
        struct Container {
            @Provide(.shared, factory: Service(), concrete: /* preserve intent */ true)
            var service: Service
        }
        """
        let root = try makeTemporaryTree(files: ["Comment.swift": source])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = try InnoDIMigrator().run(root: root, mode: .write)
        #expect(plan.diagnostics.map(\.code) == ["migrate.concrete-argument-unsupported"])
        #expect(plan.changes.isEmpty)
        #expect(
            try String(contentsOf: root.appendingPathComponent("Comment.swift"), encoding: .utf8)
                == source
        )
    }

    @Test("Ambiguous feature-root configurations block migration")
    func ambiguousFeatureRootsBlockMigration() throws {
        let source = """
        import InnoDISwiftUI

        @SubContainer(scope: .shared, featureRoot: ExistingView.self)
        @DIFeatureRoot(LegacyView.self)
        var feature: FeatureContainer
        """
        let root = try makeTemporaryTree(files: ["Feature.swift": source])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = try InnoDIMigrator().run(root: root, mode: .write)
        #expect(plan.diagnostics.map(\.code) == ["migrate.feature-root-ambiguous"])
        #expect(plan.changes.isEmpty)
        #expect(
            try String(contentsOf: root.appendingPathComponent("Feature.swift"), encoding: .utf8)
                == source
        )
    }

    @Test("A SubContainer line comment blocks feature-root migration")
    func subContainerLineCommentBlocksMigration() throws {
        let source = """
        import InnoDISwiftUI

        @SubContainer(
            scope: .shared // preserve lifetime intent
        )
        @DIFeatureRoot(FeatureView.self)
        var feature: FeatureContainer
        """
        let root = try makeTemporaryTree(files: ["Feature.swift": source])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = try InnoDIMigrator().run(root: root, mode: .write)
        #expect(plan.diagnostics.map(\.code) == ["migrate.feature-root-ambiguous"])
        #expect(plan.changes.isEmpty)
        #expect(
            try String(contentsOf: root.appendingPathComponent("Feature.swift"), encoding: .utf8)
                == source
        )
    }

    @Test("Duplicate feature-root helper identities block migration")
    func duplicateFeatureRootHelpersBlockMigration() throws {
        let source = """
        import InnoDISwiftUI

        @SubContainer(scope: .shared)
        @DIFeatureRoot(FirstView.self, as: "shell")
        @DIFeatureRoot(SecondView.self, as: "shell")
        var feature: FeatureContainer
        """
        let root = try makeTemporaryTree(files: ["Feature.swift": source])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = try InnoDIMigrator().plan(root: root)
        #expect(plan.diagnostics.map(\.code) == ["migrate.feature-root-ambiguous"])
        #expect(plan.changes.isEmpty)
    }

    @Test("Generic feature-root types migrate")
    func genericFeatureRootMigrates() throws {
        let source = """
        import InnoDISwiftUI

        @SubContainer(scope: .shared)
        @DIFeatureRoot(GenericRootView<Model>.self)
        var feature: FeatureContainer
        """
        let root = try makeTemporaryTree(files: ["Feature.swift": source])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = try InnoDIMigrator().plan(root: root)
        let migrated = try #require(plan.changes.first?.migratedSource)
        #expect(plan.diagnostics.isEmpty)
        #expect(migrated.contains("featureRoot: GenericRootView<Model>.self"))
    }

    @Test("A parse error blocks otherwise safe writes")
    func parseErrorBlocksEveryWrite() throws {
        let safeSource = """
        import InnoDI
        @DIContainer
        struct Container {
            @Provide(.shared, factory: Service(), concrete: true)
            var service: Service
        }
        """
        let invalidSource = "struct Broken {"
        let root = try makeTemporaryTree(files: [
            "Safe.swift": safeSource,
            "Invalid.swift": invalidSource,
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = try InnoDIMigrator().run(root: root, mode: .write)
        #expect(plan.changes.isEmpty)
        #expect(plan.diagnostics.map(\.code) == ["migrate.parse-error"])
        #expect(
            try String(contentsOf: root.appendingPathComponent("Safe.swift"), encoding: .utf8)
                == safeSource
        )
    }

    @Test("Swift sources in a legitimately named DerivedData directory are scanned")
    func derivedDataSourceDirectoryIsScanned() throws {
        let root = try makeTemporaryTree(files: [
            "Sources/DerivedData/Legacy.swift": """
            import InnoDI
            @DIContainer
            struct Container {
                @Provide(.shared, factory: Service(), concrete: true)
                var service: Service
            }
            """,
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = try InnoDIMigrator().plan(root: root)
        #expect(plan.diagnostics.isEmpty)
        #expect(plan.changes.map(\.path) == ["Sources/DerivedData/Legacy.swift"])
    }

    @Test("Non-source and excluded-directory symlinks are ignored")
    func harmlessSymlinksAreIgnored() throws {
        let source = """
        import InnoDI
        @DIContainer
        struct Container {
            @Provide(.shared, factory: Service(), concrete: true)
            var service: Service
        }
        """
        let root = try makeTemporaryTree(files: [
            "Sources/App/App.swift": source,
            "Shared/README-target.md": "documentation",
        ])
        let externalBuild = try makeTemporaryTree(files: ["Generated.swift": source])
        defer { try? FileManager.default.removeItem(at: root) }
        defer { try? FileManager.default.removeItem(at: externalBuild) }
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("README.md"),
            withDestinationURL: root.appendingPathComponent("Shared/README-target.md")
        )
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent(".build"),
            withDestinationURL: externalBuild
        )

        let plan = try InnoDIMigrator().run(root: root, mode: .write)
        #expect(plan.diagnostics.isEmpty)
        #expect(plan.changes.map(\.path) == ["Sources/App/App.swift"])
        #expect(
            try String(contentsOf: root.appendingPathComponent("Shared/README-target.md"), encoding: .utf8)
                == "documentation"
        )
        #expect(
            try String(contentsOf: externalBuild.appendingPathComponent("Generated.swift"), encoding: .utf8)
                == source
        )
    }

    @Test("A Swift source symlink aborts before any write")
    func sourceSymlinkBlocksEveryWrite() throws {
        let source = """
        import InnoDI
        @DIContainer
        struct Container {
            @Provide(.shared, factory: Service(), concrete: true)
            var service: Service
        }
        """
        let root = try makeTemporaryTree(files: [
            "Safe.swift": source,
            "Targets/LinkedTarget.swift": source,
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Linked.swift"),
            withDestinationURL: root.appendingPathComponent("Targets/LinkedTarget.swift")
        )

        #expect(throws: MigrationError.self) {
            try InnoDIMigrator().run(root: root, mode: .write)
        }
        #expect(
            try String(contentsOf: root.appendingPathComponent("Safe.swift"), encoding: .utf8)
                == source
        )
    }

    @Test("A symlinked root resolves to one canonical migration tree")
    func symlinkedRootIsResolved() throws {
        let source = """
        import InnoDI
        @DIContainer
        struct Container {
            @Provide(.shared, factory: Service(), concrete: true)
            var service: Service
        }
        """
        let root = try makeTemporaryTree(files: ["Sources/App/App.swift": source])
        let alias = FileManager.default.temporaryDirectory.appendingPathComponent(
            "InnoDI-MigrationRoot-\(UUID().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: alias) }
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(
            at: alias,
            withDestinationURL: root
        )

        let migrator = InnoDIMigrator()
        let check = try migrator.plan(root: alias)
        #expect(check.changes.map(\.path) == ["Sources/App/App.swift"])
        _ = try migrator.run(root: alias, mode: .write)
        #expect(try migrator.plan(root: alias).changes.isEmpty)
    }

    @Test("A linked source directory aborts before any write")
    func sourceDirectorySymlinkBlocksEveryWrite() throws {
        let source = """
        import InnoDI
        @DIContainer
        struct Container {
            @Provide(.shared, factory: Service(), concrete: true)
            var service: Service
        }
        """
        let root = try makeTemporaryTree(files: ["Safe.swift": source])
        let external = try makeTemporaryTree(files: ["External.swift": source])
        defer { try? FileManager.default.removeItem(at: root) }
        defer { try? FileManager.default.removeItem(at: external) }
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("SourcesAlias"),
            withDestinationURL: external
        )

        #expect(throws: MigrationError.self) {
            try InnoDIMigrator().run(root: root, mode: .write)
        }
        #expect(
            try String(contentsOf: root.appendingPathComponent("Safe.swift"), encoding: .utf8)
                == source
        )
    }

    @Test("Nested Git repositories are not traversed or rewritten")
    func nestedRepositoriesAreSkipped() throws {
        let source = """
        import InnoDI
        @DIContainer
        struct Container {
            @Provide(.shared, factory: Service(), concrete: true)
            var service: Service
        }
        """
        let root = try makeTemporaryTree(files: [
            "Sources/App/App.swift": source,
            "Vendor/Dependency/.git": "gitdir: ../../.git/modules/Dependency",
            "Vendor/Dependency/Legacy.swift": source,
            "Vendor/Dependency/Target.swift": source,
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Vendor/Dependency/Linked.swift"),
            withDestinationURL: root.appendingPathComponent("Vendor/Dependency/Target.swift")
        )

        let plan = try InnoDIMigrator().run(root: root, mode: .write)
        #expect(plan.diagnostics.isEmpty)
        #expect(plan.changes.map(\.path) == ["Sources/App/App.swift"])
        #expect(
            try String(contentsOf: root.appendingPathComponent("Vendor/Dependency/Legacy.swift"), encoding: .utf8)
                == source
        )
    }

    @Test("UTF-8 byte-order marks survive atomic migration writes")
    func byteOrderMarkIsPreserved() throws {
        let source = """
        import InnoDI
        @DIContainer
        struct Container {
            @Provide(.shared, factory: Service(), concrete: true)
            var service: Service
        }
        """
        let root = try makeTemporaryTree(files: ["BOM.swift": source])
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("BOM.swift")
        var originalData = Data([0xEF, 0xBB, 0xBF])
        originalData.append(try #require(source.data(using: .utf8)))
        try originalData.write(to: fileURL)

        let plan = try InnoDIMigrator().run(root: root, mode: .write)
        #expect(plan.diagnostics.isEmpty)
        let migratedData = try Data(contentsOf: fileURL)
        #expect(migratedData.starts(with: [0xEF, 0xBB, 0xBF]))
        #expect(!String(decoding: migratedData, as: UTF8.self).contains("concrete:"))
    }

    @Test("A write-time source change rolls back earlier tool output")
    func writeTimeChangeRollsBackEarlierWrites() throws {
        let firstSource = migratableProviderSource(containerName: "FirstContainer")
        let secondSource = migratableProviderSource(containerName: "SecondContainer")
        let editorUpdate = "// editor update\nstruct SecondContainer {}\n"
        let root = try makeTemporaryTree(files: [
            "A.swift": firstSource,
            "B.swift": secondSource,
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(throws: MigrationError.self) {
            try InnoDIMigrator().run(
                root: root,
                mode: .write,
                beforeWritingChange: { _, index in
                    if index == 1 {
                        try editorUpdate.write(
                            to: root.appendingPathComponent("B.swift"),
                            atomically: true,
                            encoding: .utf8
                        )
                    }
                }
            )
        }
        #expect(
            try String(contentsOf: root.appendingPathComponent("A.swift"), encoding: .utf8)
                == firstSource
        )
        #expect(
            try String(contentsOf: root.appendingPathComponent("B.swift"), encoding: .utf8)
                == editorUpdate
        )
    }

    @Test("Rollback preserves a concurrent edit to an earlier migrated file")
    func rollbackPreservesConcurrentEditorUpdate() throws {
        let firstSource = migratableProviderSource(containerName: "FirstContainer")
        let secondSource = migratableProviderSource(containerName: "SecondContainer")
        let firstEditorUpdate = "// editor replaced first\nstruct FirstContainer {}\n"
        let secondEditorUpdate = "// editor replaced second\nstruct SecondContainer {}\n"
        let root = try makeTemporaryTree(files: [
            "A.swift": firstSource,
            "B.swift": secondSource,
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(throws: MigrationError.self) {
            try InnoDIMigrator().run(
                root: root,
                mode: .write,
                beforeWritingChange: { _, index in
                    if index == 1 {
                        try firstEditorUpdate.write(
                            to: root.appendingPathComponent("A.swift"),
                            atomically: true,
                            encoding: .utf8
                        )
                        try secondEditorUpdate.write(
                            to: root.appendingPathComponent("B.swift"),
                            atomically: true,
                            encoding: .utf8
                        )
                    }
                }
            )
        }
        #expect(
            try String(contentsOf: root.appendingPathComponent("A.swift"), encoding: .utf8)
                == firstEditorUpdate
        )
        #expect(
            try String(contentsOf: root.appendingPathComponent("B.swift"), encoding: .utf8)
                == secondEditorUpdate
        )
    }

    @Test("Public migration executable runs from a fresh dependency consumer")
    func publicExecutableRunsFromFreshConsumer() throws {
        let packageRoot = innoDIPackageRootURL()
        let packageIdentity = packageRoot.lastPathComponent.lowercased()
        let escapedPackagePath = escapedSwiftString(
            packageRoot.path(percentEncoded: false)
        )
        let consumerRoot = try makeTemporaryTree(files: [
            "Package.swift": """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "MigrationConsumer",
                platforms: [.macOS(.v14)],
                dependencies: [
                    .package(path: "\(escapedPackagePath)")
                ],
                targets: [
                    .executableTarget(
                        name: "Fixture",
                        dependencies: [
                            .product(name: "InnoDI", package: "\(packageIdentity)"),
                            .product(name: "InnoDISwiftUI", package: "\(packageIdentity)")
                        ]
                    )
                ]
            )
            """,
            "Sources/Fixture/Fixture.swift": """
            import InnoDISwiftUI

            protocol ServiceProtocol {}
            struct Service: ServiceProtocol {}

            @DIContainer
            struct FeatureContainer {}

            struct FeatureRootView: View {
                let container: FeatureContainer

                var body: some View {
                    EmptyView()
                }
            }

            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: Service(), concrete: true)
                var service: any ServiceProtocol

                @SubContainer(scope: .shared, with: [])
                @DIFeatureRoot(FeatureRootView.self)
                var feature: FeatureContainer
            }

            @main
            struct Fixture {
                static func main() {}
            }
            """,
        ])
        defer { try? FileManager.default.removeItem(at: consumerRoot) }

        let initialCheck = try runMigrationCommand(
            packageURL: consumerRoot,
            mode: "--check"
        )
        #expect(!initialCheck.timedOut, Comment(rawValue: initialCheck.output))
        #expect(initialCheck.exitCode == 1, Comment(rawValue: initialCheck.output))
        #expect(
            initialCheck.output.contains(
                "MIGRATE Sources/Fixture/Fixture.swift [migrate.source-update]"
            ),
            Comment(rawValue: initialCheck.output)
        )

        let fixtureURL = consumerRoot.appendingPathComponent("Sources/Fixture/Fixture.swift")
        let sourceBeforeReport = try Data(contentsOf: fixtureURL)
        let reportURL = consumerRoot.appendingPathComponent("migration-report.json")
        let reportCommand = try runMigrationCommand(
            packageURL: consumerRoot,
            mode: "--report",
            additionalArguments: ["--output", reportURL.path(percentEncoded: false)]
        )
        #expect(!reportCommand.timedOut, Comment(rawValue: reportCommand.output))
        #expect(reportCommand.exitCode == 1, Comment(rawValue: reportCommand.output))
        let report = try JSONDecoder().decode(
            MigrationReport.self,
            from: Data(contentsOf: reportURL)
        )
        #expect(report.status == .changesRequired)
        #expect(report.changes.map(\.path) == ["Sources/Fixture/Fixture.swift"])
        #expect(report.diagnostics.isEmpty)
        #expect(try Data(contentsOf: fixtureURL) == sourceBeforeReport)

        let write = try runMigrationCommand(
            packageURL: consumerRoot,
            mode: "--write"
        )
        #expect(!write.timedOut, Comment(rawValue: write.output))
        #expect(write.exitCode == 0, Comment(rawValue: write.output))
        #expect(
            write.output.contains(
                "MIGRATED Sources/Fixture/Fixture.swift [migrate.source-update]"
            ),
            Comment(rawValue: write.output)
        )

        let finalCheck = try runMigrationCommand(
            packageURL: consumerRoot,
            mode: "--check"
        )
        #expect(!finalCheck.timedOut, Comment(rawValue: finalCheck.output))
        #expect(finalCheck.exitCode == 0, Comment(rawValue: finalCheck.output))

        let migrated = try String(
            contentsOf: fixtureURL,
            encoding: .utf8
        )
        #expect(!migrated.contains("concrete:"))
        #expect(!migrated.contains("DIFeatureRoot"))
        #expect(migrated.contains("featureRoot: FeatureRootView.self"))

        let build = try runConsumerBuild(packageURL: consumerRoot)
        #expect(!build.timedOut, Comment(rawValue: build.output))
        #expect(build.exitCode == 0, Comment(rawValue: build.output))
    }
}

private struct MigrationProcessResult {
    let exitCode: Int32
    let output: String
    let timedOut: Bool
}

private func migratableProviderSource(containerName: String) -> String {
    """
    import InnoDI
    @DIContainer
    struct \(containerName) {
        @Provide(.shared, factory: Service(), concrete: true)
        var service: Service
    }
    """
}

private func makeTemporaryTree(files: [String: String]) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "InnoDI-MigrationTests-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: root,
        withIntermediateDirectories: true
    )
    var completed = false
    defer {
        if !completed {
            try? FileManager.default.removeItem(at: root)
        }
    }

    for (path, contents) in files {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
    completed = true
    return root
}

private func innoDIPackageRootURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func escapedSwiftString(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}

private func runMigrationCommand(
    packageURL: URL,
    mode: String,
    additionalArguments: [String] = []
) throws -> MigrationProcessResult {
    try runSwiftProcess(
        packageURL: packageURL,
        arguments: [
            "swift",
            "run",
            "--package-path",
            packageURL.path(percentEncoded: false),
            "InnoDI-Migrate",
            "--root",
            packageURL.path(percentEncoded: false),
            mode,
        ] + additionalArguments
    )
}

private func runConsumerBuild(
    packageURL: URL
) throws -> MigrationProcessResult {
    try runSwiftProcess(
        packageURL: packageURL,
        arguments: [
            "swift",
            "build",
            "--package-path",
            packageURL.path(percentEncoded: false),
            "--product",
            "Fixture",
            "-Xswiftc",
            "-strict-concurrency=complete",
            "-Xswiftc",
            "-warnings-as-errors",
        ]
    )
}

private func runSwiftProcess(
    packageURL: URL,
    arguments: [String]
) throws -> MigrationProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    process.currentDirectoryURL = innoDIPackageRootURL()

    let result = try runCapturedProcess(
        process,
        timeoutSeconds: migrationSwiftProcessTimeoutSeconds
    )
    return MigrationProcessResult(
        exitCode: result.exitCode,
        output: result.combinedOutput,
        timedOut: result.timedOut
    )
}

// This public-consumer contract performs a cold SwiftSyntax and macro build in
// a separate SwiftPM scratch directory. GitHub's macos-26 runners can take more
// than three minutes when other external-consumer suites are active, despite
// continuing to emit compiler progress. Match the established cold-build
// allowance used by StrictConcurrencyBuildTests.
private let migrationSwiftProcessTimeoutSeconds: TimeInterval = 600
