## InnoDI Examples

### 1) DI + Macro Usage

Reference source:
- `Sources/InnoDIExamples/main.swift`

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

@DIContainer(root: true)
struct AppContainer {
    @Provide(.input)
    var config: Config

    @Provide(.shared, factory: { (config: Config) in APIClient(baseURL: config.baseURL) }, concrete: true)
    var apiClient: APIClient

    @Provide(.shared, factory: { (apiClient: APIClient) in UserService(client: apiClient) }, concrete: true)
    var userService: UserService
}

let container = AppContainer(config: Config(baseURL: "https://api.example.com"))
print("Live baseURL:", container.userService.client.baseURL)

let mockContainer = AppContainer(
    config: Config(baseURL: "https://api.example.com"),
    apiClient: APIClient(baseURL: "mock://")
)
print("Mock baseURL:", mockContainer.userService.client.baseURL)
```

Notes:
- `.input` does not accept `factory`.
- `.shared` and `.transient` require `factory`, `Type.self` + `with:`, or an initializer expression.
- For protocol-typed `.shared`/`.transient`, use explicit existential syntax (`any Protocol`).
- Concrete `.shared`/`.transient` properties require `concrete: true`.

### 2) CLI Usage (Dependency Graph Visualization)

Runnable sample files:
- `Examples/SampleApp/AppContainer.swift`
- `Examples/SampleApp/App.swift`

Run:

```bash
swift run InnoDI-DependencyGraph --root Examples/SampleApp
```

Generate different formats:

```bash
# Mermaid diagram (default)
swift run InnoDI-DependencyGraph --root /path/to/your/project

# DOT format
swift run InnoDI-DependencyGraph --root /path/to/your/project --format dot --output graph.dot

# ASCII format
swift run InnoDI-DependencyGraph --root /path/to/your/project --format ascii

# PNG image (requires Graphviz)
swift run InnoDI-DependencyGraph --root /path/to/your/project --format dot --output graph.png
```

Current CLI behavior:
- Collects all `@DIContainer` declarations and required `.input` fields.
- Builds container-to-container edges from constructor calls found in container bodies.
- Uses stable node identity (`relativeFilePath#declarationPath`) to avoid over-merging same display names.
- Skips ambiguous edges when multiple destination containers share the same display name.

You can mark a root container:

```swift
@DIContainer(root: true)
struct AppContainer { ... }
```

### 3) Core Tests (Swift Testing)

Reference files:
- `Tests/InnoDICoreTests/ParsingTests.swift`
- `Tests/InnoDICoreTests/DependencyGraphCoreTests.swift`

Run:

```bash
swift test --filter InnoDICoreTests
```

Example parsing test:

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

### 4) Macro Tests

Reference file:
- `Tests/InnoDIMacrosTests/DIContainerMacroTests.swift`

Run:

```bash
swift test --filter InnoDIMacrosTests
```

Example:

```swift
import SwiftParser
import SwiftSyntax
import Testing

@testable import InnoDIMacros

struct DIContainerMacroTests {
    @Test
    func concreteSharedDependencyRequiresOptIn() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.shared, factory: APIClient())
            var apiClient: APIClient
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse @DIContainer")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(
            of: attr,
            providingMembersOf: decl,
            in: context
        )

        #expect(generated.isEmpty)
        #expect(context.diagnostics.contains { $0.message.contains("requires concrete: true") })
    }
}
```
