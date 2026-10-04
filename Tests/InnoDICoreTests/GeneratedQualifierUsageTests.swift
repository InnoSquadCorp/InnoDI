import SwiftParser
import SwiftSyntax
import Testing

@testable import InnoDICore

@Suite("Generated qualifier usage planning")
struct GeneratedQualifierUsageTests {
    @Test("Input-only containers keep the empty builder free of extra qualifiers")
    func plainContainerHasNoBodyOrExtensionQualifiers() throws {
        let usage = try containerUsage(
            """
            @DIContainer
            struct Container {
                @Provide(.input) var value: Int
            }
            """
        )

        #expect(usage.attachedAttributes == [.init("InnoDI")])
        #expect(usage.memberBodies.isEmpty)
        #expect(usage.fileScopeExtensions.isEmpty)
    }

    @Test("Override helpers require Swift types only for builders with slots", arguments: [
        "@Provide(factory: 1) var value: Int",
        "@Provide(.transient, factory: 1) var value: Int",
        "@SubContainer(scope: .shared) var child: Child",
    ])
    func overrideHelperQualifier(_ members: String) throws {
        for attribute in ["@DIContainer", "@DIContainer(validateDAG: false)"] {
            let usage = try containerUsage("\(attribute) struct Container { \(members) }")
            #expect(usage.memberBodies == [.init("Swift", namespace: .typeOnly)])
        }
    }

    @Test("Rejected override generation does not claim its Swift qualifier", arguments: [
        "@DIContainer struct Container { @Provide(factory: 1) var value: Int; init() {} }",
        "@DIContainer struct Container { @Provide(factory: 1) var dependency: Int\n#if DEBUG\ninit() {}\n#endif\n}",
        "@DIContainer struct Container { @Provide(factory: 1) var value: Int; struct Overrides {} }",
        "@DIContainer struct Container { @Provide(factory: 1) var value: Int; typealias Overrides = Int }",
        "@DIContainer struct Container { @Provide(factory: 1) var value: Int\n#if DEBUG\nstruct Overrides {}\n#endif\n}",
        "@DIContainer struct Container { @Provide(factory: 1) var value: Int; var other = 1 }",
        "@DIContainer struct Container { @Provide(factory: 1) var value: Int; var other = 1 { didSet {} } }",
        "@DIContainer struct Container { @Provide(factory: 1) var dependency: Int\n#if DEBUG\n@Input var value: Int\n#endif\n}",
        "@DIContainer(validateDAG: flag) struct Container { @Provide(factory: 1) var value: Int }",
        "@DIContainer(generateOwned: flag) struct Container { @Provide(factory: 1) var value: Int }",
        "@DIContainer(initializationOrder: unknown) struct Container { @Provide(factory: 1) var value: Int }",
        "@DIContainer private struct Container { @Provide(factory: 1) var value: Int }",
        "@DIContainer struct Container<T> { @Provide(factory: 1) var value: Int }",
        "@DIContainer struct Container { @Provide(factory: 1) var dependency: Int; @_InnoDIProvideAccessor var value: Int }",
        "@DIContainer struct Container { @Provide(.shared, effect: .unknown, factory: 1) var value: Int }",
        "@DIContainer struct Container { @Input var value: Int; @Provide(factory: 1) var value: Int }",
    ])
    func rejectedOverrideHelpersDoNotClaimQualifier(_ source: String) throws {
        let usage = try containerUsage(source)
        #expect(usage.memberBodies.isEmpty)
    }

    @Test("Nested declarations and computed members do not suppress override helpers")
    func unrelatedDeclarationsKeepOverrideHelperQualifier() throws {
        let usage = try containerUsage("""
            @DIContainer struct Container {
                @Provide(factory: 1) var dependency: Int
                struct Payload { struct Overrides {}; init() {} }
                var value: Int { 1 }
                static var counter = 0
            }
            extension Other { init() {} }
            """)
        #expect(usage.memberBodies == [.init("Swift", namespace: .typeOnly)])
    }

    @Test("Main actor containers add the Swift body qualifier")
    func mainActorQualifier() throws {
        let usage = try containerUsage(
            """
            @DIContainer(mainActor: true)
            struct Container {
                @Provide(.input) var value: Int
            }
            """
        )

        #expect(usage.memberBodies == [.init("Swift")])
    }

    @Test("Shared async factories add Swift and concurrency qualifiers")
    func asyncSharedQualifiers() throws {
        let usage = try containerUsage(
            """
            @DIContainer
            struct Container {
                @Provide(asyncFactory: { () async -> Int in 1 })
                var value: Int
            }
            """
        )

        #expect(usage.memberBodies == [
            .init("Swift"),
            .init("_Concurrency"),
        ])
    }

    @Test("On-demand shared providers need InnoDI in type and value lookups")
    func onDemandSharedQualifiers() throws {
        let sync = try containerUsage(
            """
            @DIContainer
            struct Container {
                @Provide(.shared, initialization: .onDemand, factory: { 1 })
                var value: Int
            }
            """
        )
        #expect(sync.memberBodies == [
            .init("InnoDI", namespace: .typeOrValue),
            .init("Swift", namespace: .typeOnly),
        ])

        let async = try containerUsage(
            """
            @DIContainer
            struct Container {
                @Provide(.shared, initialization: .onDemand, asyncFactory: { () async -> Int in 1 })
                var value: Int
            }
            """
        )
        #expect(async.memberBodies == [
            .init("Swift"),
            .init("_Concurrency"),
            .init("InnoDI", namespace: .typeOrValue),
        ])
    }

    @Test("Transient async factories require only the typed override qualifier")
    func transientAsyncHasOnlyOverrideBodyQualifier() throws {
        let usage = try containerUsage(
            """
            @DIContainer
            struct Container {
                @Provide(.transient, asyncFactory: { () async -> Int in 1 })
                var value: Int
            }
            """
        )

        #expect(usage.memberBodies == [.init("Swift", namespace: .typeOnly)])
    }

    @Test("Deferred cells require Swift types and InnoDI runtime support")
    func deferredCellQualifiers() throws {
        let usage = try containerUsage(
            """
            @DIContainer
            struct Container {
                @Provide(.transient, factory: { 1 })
                var dependency: Int

                @Provide(factory: { (dependency: Provider<Int>) in
                    dependency()
                })
                var value: Int
            }
            """
        )

        #expect(usage.memberBodies == [
            .init("Swift"),
            .init("InnoDI", namespace: .typeOrValue),
        ])
    }

    @Test("Only transient subcontainers emit deferred cell support")
    func subContainerScopeQualifiers() throws {
        let shared = try containerUsage(
            """
            @DIContainer
            struct Container {
                @SubContainer(scope: .shared) var child: Child
            }
            """
        )
        let transient = try containerUsage(
            """
            @DIContainer
            struct Container {
                @SubContainer(scope: .transient) var child: Child
            }
            """
        )

        #expect(shared.memberBodies == [.init("Swift", namespace: .typeOnly)])
        #expect(transient.memberBodies == [
            .init("Swift"),
            .init("InnoDI", namespace: .typeOrValue),
        ])
    }

    @Test("DAG opt-out adds runtime support only for an emitted fallback")
    func unresolvedFallbackQualifier() throws {
        let resolved = try containerUsage(
            """
            @DIContainer(validateDAG: false)
            struct Container {
                @Provide(.input) var dependency: Int
                @Provide(factory: { dependency in dependency }) var value: Int
            }
            """
        )
        let unresolved = try containerUsage(
            """
            @DIContainer(validateDAG: false)
            struct Container {
                @Provide(factory: { missing in missing }) var value: Int
            }
            """
        )

        #expect(resolved.memberBodies == [.init("Swift", namespace: .typeOnly)])
        #expect(unresolved.memberBodies == [
            .init("Swift", namespace: .typeOnly),
            .init("InnoDI", namespace: .typeOrValue),
        ])
    }

    @Test("Dependency-order forward edges do not generate unresolved fallbacks", arguments: [false, true])
    func dependencyOrderForwardQualifier(isAsync: Bool) throws {
        let factoryLabel = isAsync ? "asyncFactory" : "factory"
        let effect = isAsync ? "async" : ""
        let members = """
            @Provide(.shared, \(factoryLabel): { (later: Int) \(effect) in later }) var first: Int
            @Provide(.shared, \(factoryLabel): { () \(effect) in 1 }) var later: Int
            """
        let dependencyOrder = try containerUsage("""
            @DIContainer(validateDAG: false, initializationOrder: ContainerInitializationOrder.dependency)
            struct Container { \(members) }
            """)
        let declarationOrder = try containerUsage("""
            @DIContainer(validateDAG: false)
            struct Container { \(members) }
            """)
        #expect(!dependencyOrder.memberBodies.contains(.init("InnoDI", namespace: .typeOrValue)))
        #expect(declarationOrder.memberBodies.contains(.init("InnoDI", namespace: .typeOrValue)))
    }

    @Test("Dependency-order qualifier analysis retains actual fallback requirements", arguments: [
        "@Provide(.shared, factory: { (missing: Int) in missing }) var first: Int",
        "@Provide(.shared, factory: { (transient: Int) in transient }) var first: Int; @Provide(.transient, factory: 1) var transient: Int",
    ])
    func dependencyOrderFallbackQualifier(_ members: String) throws {
        let usage = try containerUsage("""
            @DIContainer(validateDAG: false, initializationOrder: ContainerInitializationOrder.dependency)
            struct Container { \(members) }
            """)
        #expect(usage.memberBodies.contains(.init("InnoDI", namespace: .typeOrValue)))
    }

    @Test("Dependency-order Type.self wiring does not claim fallback qualifiers")
    func dependencyOrderWithQualifier() throws {
        let usage = try containerUsage("""
            @DIContainer(validateDAG: false, initializationOrder: ContainerInitializationOrder.dependency)
            struct Container {
                @Provide(.shared, Service.self, with: [\\Self.later]) var service: Service
                @Provide(.shared, factory: 1) var later: Int
            }
            """)
        #expect(!usage.memberBodies.contains(.init("InnoDI", namespace: .typeOrValue)))
    }

    @Test("Opt-in does not mistake a storage-prefixed recovery name for a topo edge")
    func dependencyOrderStorageFallbackQualifier() throws {
        let usage = try containerUsage("""
            @DIContainer(validateDAG: false, initializationOrder: ContainerInitializationOrder.dependency)
            struct Container {
                @Provide(.shared, factory: { (_storage_later: Int) in _storage_later }) var first: Int
                @Provide(.shared, factory: 1) var later: Int
            }
            """)
        #expect(usage.memberBodies.contains(.init("InnoDI", namespace: .typeOrValue)))
        let inputUsage = try containerUsage("""
            @DIContainer(validateDAG: false, initializationOrder: ContainerInitializationOrder.dependency)
            struct Container {
                @Provide(.shared, factory: { (_storage_input: Int) in _storage_input }) var first: Int
                @Input var input: Int
            }
            """)
        #expect(!inputUsage.memberBodies.contains(.init("InnoDI", namespace: .typeOrValue)))
    }

    @Test("Sync dependencies mirror generated storage-name normalization")
    func syncStorageNamesDoNotEmitFallbacks() throws {
        let usage = try containerUsage(
            """
            @DIContainer(validateDAG: false)
            struct Container {
                @Provide(.input) var value: Int

                @Provide(factory: { (_storage_value: Int) in _storage_value })
                var copy: Int

                @Provide(.shared, Service.self, with: [\\Self._storage_value])
                var service: Service
            }
            """
        )

        #expect(usage.memberBodies == [.init("Swift", namespace: .typeOnly)])
    }

    @Test("Async dependencies preserve exact dependency names")
    func asyncStorageNamesStillEmitFallbacks() throws {
        let usage = try containerUsage(
            """
            @DIContainer(validateDAG: false)
            struct Container {
                @Provide(.input) var value: Int

                @Provide(asyncFactory: {
                    (_storage_value: Int) async in _storage_value
                })
                var copy: Int
            }
            """
        )

        #expect(usage.memberBodies == [
            .init("Swift"),
            .init("_Concurrency"),
            .init("InnoDI", namespace: .typeOrValue),
        ])
    }

    @Test("Conditional managed members do not emit generated support")
    func conditionalMembersAreIgnored() throws {
        let usage = try containerUsage(
            """
            @DIContainer
            struct Container {
            #if DEBUG
                @Provide(asyncFactory: { () async -> Int in 1 })
                var value: Int

                @SubContainer(scope: .transient) var child: Child
            #endif
            }
            """
        )

        #expect(usage.attachedAttributes.isEmpty)
        #expect(usage.memberBodies.isEmpty)
        #expect(usage.fileScopeExtensions.isEmpty)
    }

    @Test("Invalid managed members do not claim container-owned qualifiers")
    func invalidMembersDoNotClaimContainerOwnedQualifiers() throws {
        let usage = try containerUsage(
            """
            @DIContainer
            struct Container {
                @Provide(asyncFactory: { 1 })
                var invalidAsync: Int

                @SubContainer(
                    scope: .transient,
                    with: [\\.value],
                    bindings: [(child: \\.value, parent: \\.value)]
                )
                var invalidChild: Child
            }
            """
        )

        #expect(usage.attachedAttributes == [.init("InnoDI")])
        #expect(usage.memberBodies.isEmpty)
        #expect(usage.fileScopeExtensions.isEmpty)
    }

    @Test("Main actor support remains emitted for invalid managed members")
    func mainActorSupportSurvivesInvalidMembers() throws {
        let usage = try containerUsage(
            """
            @DIContainer(mainActor: true)
            struct Container {
                @Provide(asyncFactory: { 1 })
                var invalidAsync: Int

                @SubContainer(scope: .transient)
                let invalidChild: Child
            }
            """
        )

        #expect(usage.memberBodies == [.init("Swift")])
    }

    @Test("Valid async peers survive an invalid container-owned sibling")
    func validAsyncPeerSurvivesInvalidSibling() throws {
        let usage = try containerUsage(
            """
            @DIContainer
            struct Container {
                @Provide(asyncFactory: { () async -> Int in 1 })
                var asyncValue: Int

                @SubContainer(
                    scope: .transient,
                    with: [\\.value],
                    bindings: [(child: \\.value, parent: \\.value)]
                )
                var invalidChild: Child
            }
            """
        )

        #expect(usage.memberBodies == [
            .init("Swift"),
            .init("_Concurrency"),
        ])
    }

    @Test("Hierarchy conformances are file-scope type lookups")
    func hierarchyExtensionQualifier() throws {
        let component = try containerUsage(
            """
            @DIComponent
            @DIContainer
            struct Container {}
            """
        )
        let root = try containerUsage(
            """
            @DIHierarchyRoot
            @DIContainer
            struct Container {}
            """
        )

        #expect(component.fileScopeExtensions == [.init("InnoDI")])
        #expect(root.fileScopeExtensions == [.init("InnoDI")])
    }

    @Test("Standalone and stacked bridges keep one Swift diagnostic owner")
    func bridgeQualifierOwnership() throws {
        let standalone = GeneratedQualifierUsage.environmentBridge(
            isContainer: false
        )
        let bridgeHalf = GeneratedQualifierUsage.environmentBridge(
            isContainer: true
        )
        let containerHalf = try containerUsage(
            """
            @InnoDISwiftUI.DIEnvironmentBridge([])
            @DIContainer
            struct Container {}
            """
        )

        #expect(standalone.memberBodies == [
            .init("Swift"),
            .init("SwiftUI"),
        ])
        #expect(standalone.fileScopeExtensions == [.init("InnoDISwiftUI")])
        #expect(bridgeHalf.memberBodies == [.init("SwiftUI")])
        #expect(containerHalf.memberBodies == [.init("Swift")])
    }
}

private enum GeneratedQualifierUsageTestError: Error {
    case missingContainer
}

private func containerUsage(
    _ source: String
) throws -> GeneratedQualifierUsage {
    let file = Parser.parse(source: source)
    guard let declaration = file.statements.compactMap({ item in
        item.item.as(StructDeclSyntax.self)
    }).first else {
        throw GeneratedQualifierUsageTestError.missingContainer
    }
    return .container(declaration: declaration)
}
