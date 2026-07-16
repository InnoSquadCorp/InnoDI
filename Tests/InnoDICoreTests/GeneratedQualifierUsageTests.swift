import SwiftParser
import SwiftSyntax
import Testing

@testable import InnoDICore

@Suite("Generated qualifier usage planning")
struct GeneratedQualifierUsageTests {
    @Test("Plain managed containers only record attached support attributes")
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

    @Test("Transient async factories do not emit Task support")
    func transientAsyncHasNoBodyQualifier() throws {
        let usage = try containerUsage(
            """
            @DIContainer
            struct Container {
                @Provide(.transient, asyncFactory: { () async -> Int in 1 })
                var value: Int
            }
            """
        )

        #expect(usage.memberBodies.isEmpty)
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

        #expect(shared.memberBodies.isEmpty)
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

        #expect(resolved.memberBodies.isEmpty)
        #expect(unresolved.memberBodies == [
            .init("InnoDI", namespace: .typeOrValue),
        ])
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

        #expect(usage.memberBodies.isEmpty)
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
