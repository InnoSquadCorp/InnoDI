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
- `.shared` requires `factory: <expr>` or `Type.self` with `with:`.
- The macro generates `init(...)` with optional override parameters.

Example with init override:

```swift
// Production - factory creates the instance
let container = AppContainer(config: Config(baseURL: "https://api.example.com"))

// Testing - directly inject mock
let testContainer = AppContainer(
    config: Config(baseURL: "https://test.example.com"),
    apiClient: MockAPIClient()
)
```

### 2) CLI Usage (Dependency Graph Visualization)

Runnable example:
- `Examples/SampleApp/AppContainer.swift`
- `Examples/SampleApp/App.swift`
- Run: `swift run InnoDI-DependencyGraph --root Examples/SampleApp`

Run the CLI from the package root or point it at another repo:

```bash
swift run InnoDI-DependencyGraph --root /path/to/your/project
```

Generate different formats:

```bash
# Mermaid diagram (default)
swift run InnoDI-DependencyGraph --root /path/to/your/project

# DOT format for Graphviz
swift run InnoDI-DependencyGraph --root /path/to/your/project --format dot --output graph.dot

# PNG image (requires Graphviz)
swift run InnoDI-DependencyGraph --root /path/to/your/project --format dot --output graph.png
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
    func testDIContainerGeneratesInitWithOptionalOverrideParameters() {
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
                init(foo: Foo? = nil) {
                    self._storage_foo = foo ?? Foo()
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
