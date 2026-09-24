import Foundation
import InnoDITestSupport
import Testing

@testable import InnoDIMacros

extension DIContainerMacroTests {
    @Test("A deferred collection keeps contributor order and detached transient resolvers")
    func detachedMultibindingComposition() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct Container {
                @Provide(.shared, factory: Item()) var shared: Item
                @Provide(.transient, factory: Item()) var fresh: Item
                @Multibinding([\\Self.shared, \\Self.fresh]) var items: [Item]
                @Provide(.shared, factory: { (items: InnoDI.Provider<[Item]>) in items })
                var root: InnoDI.Provider<[Item]>
            }
            """,
            macros: Self.macros.merging(["Multibinding": ProvideMacro.self]) { _, new in new }
        )
        #expect(result.diagnostics.isEmpty)
        #expect(result.expansion.contains("items ?? [_innoDIResolverValue_shared, _innoDIResolver_fresh()]"))
        #expect(result.expansion.contains("_innoDILazyCell_items.bindResolver(_innoDIResolver_items)"))
        #expect(!result.expansion.contains("_lazySelf"))
    }

    @Test("A detached transient can itself depend on qualified Lazy and Provider handles")
    func detachedNestedDeferredComposition() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct Container {
                @Provide(.shared, factory: Item()) var shared: Item
                @Provide(.transient, factory: Item()) var fresh: Item
                @Provide(.transient, factory: { (shared: InnoDI.Lazy<Item>, fresh: InnoDI.Provider<Item>) in
                    Handles(shared: shared, fresh: fresh)
                }) var handles: Handles
                @Provide(.shared, factory: { (handles: InnoDI.Provider<Handles>) in handles })
                var root: InnoDI.Provider<Handles>
            }
            """,
            macros: Self.macros
        )
        #expect(result.diagnostics.isEmpty)
        let compact = result.expansion.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        #expect(compact.contains("let_innoDIResolver_handles:()->Handles="))
        #expect(compact.contains("}(.init{_innoDILazyCell_shared.resolve()},.init{_innoDILazyCell_fresh.resolve()})"))
        #expect(result.expansion.contains("_innoDILazyCell_handles.bindResolver(_innoDIResolver_handles)"))
        #expect(!result.expansion.contains("_lazySelf"))
    }
}
