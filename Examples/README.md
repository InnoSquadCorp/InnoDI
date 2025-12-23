## InnoDI Examples

### 1) DI + Macro Usage

Runnable example:
- `Sources/InnoDIExamples/main.swift`
- Run: `swift run InnoDIExamples`

```swift
import InnoDI

struct Config {
    let baseURL: String
}

struct APIClient {
    let baseURL: String
}

struct UserService {
    let client: APIClient
}

@DIContainer
struct AppContainer {
    @Provide(.input)
    var config: Config

    @Provide(.shared, factory: APIClient(baseURL: config.baseURL))
    var apiClient: APIClient

    @Provide(.shared, factory: UserService(client: apiClient))
    var userService: UserService
}

let container = AppContainer(config: Config(baseURL: "https://api.example.com"))
let service = container.userService
```

Notes:
- `.input` requires no `factory`.
- `.shared` requires `factory: <expr>`.
- The macro generates `init(...)` and an `Overrides` struct for shared members.

Example with overrides (shared only):

```swift
var overrides = AppContainer.Overrides()
overrides.apiClient = APIClient(baseURL: "mock://")
let container = AppContainer(overrides: overrides, config: Config(baseURL: "https://api.example.com"))
```

### 2) CLI Usage (Static Analysis)

Runnable example:
- `Examples/SampleApp/AppContainer.swift`
- `Examples/SampleApp/App.swift`
- Run: `swift run InnoDICLI --root Examples/SampleApp`

Run the CLI from the package root or point it at another repo:

```bash
swift run InnoDICLI --root /path/to/your/project
```

The CLI reports:
- Missing required `.input` arguments when constructing containers.
- Containers that are not reachable from any root container.

You can mark a container as a root:

```swift
@DIContainer(root: true)
struct AppContainer { ... }
```

### 3) Core Parsing Tests (SwiftTesting)

Runnable example:
- `Tests/InnoDIExamplesTests/ExampleTests.swift`
- Run: `swift test --filter InnoDIExamplesTests`

```swift
import SwiftParser
import SwiftSyntax
import Testing
@testable import InnoDICore

struct ParsingTests {
    @Test
    func parseProvideAttributeInput() {
        let source = """
        struct AppContainer {
            @Provide(.input)
            var config: Config
        }
        """

        let file = Parser.parse(source: source)
        let structDecl = file.statements.compactMap { $0.item.as(StructDeclSyntax.self) }.first
        let varDecl = structDecl?.memberBlock.members.compactMap { $0.decl.as(VariableDeclSyntax.self) }.first

        let info = InnoDICore.parseProvideAttribute(varDecl?.attributes)
        #expect(info.hasProvide == true)
        #expect(info.scope == .input)
    }
}
```

Run:

```bash
swift test
```

### 4) Macro Expansion Tests (CI-only by default)

```swift
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import InnoDIMacros

final class DIContainerMacroTests: XCTestCase {
    func testDIContainerGeneratesInitAndOverrides() {
        let macros: [String: Macro.Type] = [
            "DIContainer": DIContainerMacro.self,
        ]

        assertMacroExpansion(
            """
            struct Foo {}
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: Foo())
                var foo: Foo
            }
            """,
            expandedSource: """
            struct Foo {}
            struct AppContainer {
                @Provide(.shared, factory: Foo())
                var foo: Foo
                struct Overrides {
                    var foo: Foo?
                    init() {
                    }
                }
                init(overrides: Overrides = .init()) {
                    let foo = overrides.foo ?? Foo()
                    self.foo = foo
                }
            }
            """,
            macros: macros
        )
    }
}
```

Run (CI-style):

```bash
INNODI_RUN_MACRO_TESTS=1 swift test --filter InnoDIMacrosTests
```
