//
//  DIContainerMacroTests.swift
//  InnoDIMacrosTests
//

import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import InnoDIMacros

final class DIContainerMacroTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        let env = ProcessInfo.processInfo.environment
        if env["INNODI_RUN_MACRO_TESTS"] != "1" {
            throw XCTSkip("Set INNODI_RUN_MACRO_TESTS=1 to run macro tests.")
        }
    }

    func testDIContainerGeneratesInitAndOverrides() {
        let macros: [String: Macro.Type] = [
            "DIContainer": DIContainerMacro.self,
        ]

        assertMacroExpansion(
            """
            struct Foo {}
            struct Bar {}

            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: Foo())
                var foo: Foo

                @Provide(.input)
                var bar: Bar
            }
            """,
            expandedSource: """
            struct Foo {}
            struct Bar {}

            struct AppContainer {
                @Provide(.shared, factory: Foo())
                var foo: Foo

                @Provide(.input)
                var bar: Bar

                struct Overrides {
                    var foo: Foo?
                    init() {
                    }
                }

                init(overrides: Overrides = .init(), bar: Bar) {
                    let foo = overrides.foo ?? Foo()
                    self.bar = bar
                    self.foo = foo
                }
            }
            """,
            macros: macros
        )
    }

    func testDIContainerStopsOnInvalidProvide() {
        let macros: [String: Macro.Type] = [
            "DIContainer": DIContainerMacro.self,
        ]

        assertMacroExpansion(
            """
            struct Foo {}

            @DIContainer
            struct AppContainer {
                @Provide(.shared)
                var foo: Foo
            }
            """,
            expandedSource: """
            struct Foo {}

            struct AppContainer {
                @Provide(.shared)
                var foo: Foo
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@Provide(.shared) requires factory: <expr>.", line: 6, column: 5),
            ],
            macros: macros
        )
    }
}
