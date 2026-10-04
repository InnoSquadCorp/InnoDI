import InnoDICore
import SwiftParser
import Testing

@testable import InnoDIDependencyGraphCore

@Suite("Declaration-local collection metadata")
struct ContainerCollectorDeclarationTests {
    @Test("Mutually exclusive declarations retain their own contributor lifetimes")
    func conditionalDeclarationsDoNotShareProviders() throws {
        let collector = collect("""
        #if DEBUG
        @DIContainer struct App {
            @Provide(.shared, factory: Service()) var service: Service
            @Provide(.transient, collection: .ordered([\\Self.service]), factory: makeProviders())
            var services: DIOrderedCollection<Service>
        }
        #else
        @DIContainer struct App {
            @Provide(.transient, factory: Service()) var service: Service
            @Provide(.transient, collection: .ordered([\\Self.service]), factory: makeProviders())
            var services: DIOrderedCollection<Service>
        }
        #endif
        """)
        #expect(collector.nodes.count == 2)
        #expect(collector.nodes[0].id == collector.nodes[1].id)
        let collections = collector.providers.filter { $0.name == "services" }
        #expect(collections.count == 2)
        let first = try #require(collections.first?.collection)
        let second = try #require(collections.last?.collection)
        #expect(first.entries.first?.providerLifetime == .shared)
        #expect(second.entries.first?.providerLifetime == .transient)
        // This collector does not select a build configuration or suppress
        // duplicate-identity validation. It must preserve both declarations.
        #expect(collector.providers.count == 4)
    }

    @Test("Invalid duplicate members never trap or choose a collection winner")
    func duplicateMembersRemainAvailableForValidation() throws {
        let collector = collect("""
        @DIContainer struct App {
            @Provide(.shared, factory: Service()) var service: Service
            @Provide(.transient, factory: Service()) var service: Service
            @Provide(.transient, collection: .ordered([\\Self.service]), factory: makeProviders())
            var services: DIOrderedCollection<Service>
            @Provide(.transient, collection: .ordered([]), factory: makeProviders())
            var services: DIOrderedCollection<Service>
        }
        """)
        #expect(collector.nodes.count == 1)
        #expect(collector.providers.count == 4)
        let collections = collector.providers.filter { $0.name == "services" }
        #expect(collections.allSatisfy { $0.collection == nil })
    }

    @Test("An ambiguous contributor has no inferred lifetime")
    func ambiguousContributorHasNoInventedLifetime() throws {
        let collector = collect("""
        @DIContainer struct App {
            @Provide(.shared, factory: Service()) var service: Service
            @Provide(.transient, factory: Service()) var service: Service
            @Provide(.transient, collection: .ordered([\\Self.service]), factory: makeProviders())
            var services: DIOrderedCollection<Service>
        }
        """)
        let collection = try #require(collector.providers.last?.collection)
        #expect(collection.entries.count == 1)
        #expect(collection.entries[0].providerLifetime == nil)
        #expect(collector.providers.count == 3)
    }

    @Test("A collection cannot attach metadata to a duplicate ordinary provider")
    func mixedDuplicateProviderKindsStayAmbiguous() {
        let collector = collect("""
        @DIContainer struct App {
            @Provide(.shared, factory: Service()) var service: Service
            @Provide(.transient, factory: makeCollection()) var services: DIOrderedCollection<Service>
            @Provide(.transient, collection: .ordered([\\Self.service]), factory: makeCollection())
            var services: DIOrderedCollection<Service>
        }
        """)
        let duplicates = collector.providers.filter { $0.name == "services" }
        #expect(duplicates.count == 2)
        #expect(duplicates.allSatisfy { $0.collection == nil })
    }

    private func collect(_ source: String) -> ContainerCollector {
        let collector = ContainerCollector(moduleIdentity: "App")
        collector.walkFile(relativePath: "App.swift", tree: Parser.parse(source: source))
        return collector
    }
}
