# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

InnoDI is a Swift dependency injection framework implemented using Swift macros. It provides compile-time DI container generation with a CLI dependency graph visualizer.

## Build and Test Commands

### Building
```bash
swift build                                    # Build all targets
swift build --target InnoDI                    # Build library only
swift build --target InnoDI-DependencyGraph    # Build CLI tool only
swift build --target InnoDIMacros              # Build macros only
```

### Testing
```bash
swift test                                     # Run all tests
swift test --filter InnoDICoreTests            # Run core parsing/graph tests
swift test --filter InnoDIMacrosTests          # Run macro expansion tests
```

### Macro expansion snapshots

Macro tests under `Tests/InnoDIMacrosTests/` use three assertion styles, all
provided by `Tests/TestSupport/MacroAssertions.swift`:

- `assertMacroExpansionSnapshot` — expansion is compared to a file under
  `Tests/InnoDIMacrosTests/__Snapshots__/<TestFile>/<name>.swift`. Use for full
  generated-code verification.
- `assertMacroExpansionInline` — expected source is inlined in the test body.
  Use for short expansions or when diagnostics with full `DiagnosticSpec`
  (line/column, notes, fix-its) matter.
- `assertMacroExpansionDiagnosticCodes` — asserts only the set of
  `SwiftDiagnostics.MessageID`s emitted (as a multiset). Preferred over
  message-substring matching so tests don't break when diagnostic wording
  changes.

When macro output changes intentionally, regenerate snapshot files:

```bash
Tools/record-macro-snapshots.sh                # record/refresh all snapshots
Tools/record-macro-snapshots.sh DIContainerMacroTests   # filter like swift test
```

The script runs the macro tests with `INNODI_RECORD_SNAPSHOTS=1`, which makes
the snapshot helper write current expansions to disk. Review the resulting
diff, then re-run `swift test --filter InnoDIMacrosTests` without the env var
to verify.

### Running the CLI
```bash
swift run InnoDI-DependencyGraph --root /path/to/project   # Generate dependency graph from DI containers
```

## Architecture

### Module Structure

The project uses a layered architecture with four main modules:

1. **InnoDI** (Public API)
   - Exports the `@DIContainer` and `@Provide` macro declarations
   - Defines `DIScope` enum (`.shared`, `.input`, `.transient`)
   - This is what library consumers import

2. **InnoDIMacros** (Macro Implementation)
   - `DIContainerMacro`: Member macro that generates an `init` and validates `@Provide` usage
   - `ProvideMacro`: Accessor macro that emits storage/accessor code per scope
   - `SimpleDiagnostic`: Custom diagnostic messages for macro errors
   - Depends on `InnoDICore` for shared parsing logic

3. **InnoDICore** (Shared Parsing)
   - Contains parsing utilities used by both macros and CLI
   - `parseProvideArguments()`: Extracts scope and factory from `@Provide` attributes
   - `parseDIContainerAttribute()`: Extracts validate/root flags from `@DIContainer`
   - `DependencyGraphCore`: Shared graph normalization/deduplication helpers for CLI
   - `findAttribute()`: Helper for locating attributes in syntax trees
   - This module prevents parsing logic duplication

4. **InnoDI-DependencyGraph** (Dependency Graph Visualization)
   - Generates dependency graphs from DI container usage across a codebase
   - Analyzes container relationships and generates visual graphs
   - Supports multiple output formats (Mermaid, DOT, ASCII, PNG)
   - Uses SwiftSyntax for parsing DI annotations

### How the Macros Work

**@DIContainer** generates:
- An `init` with parameters for:
  - `.input` scoped properties (required parameters)
  - `.shared` and `.transient` scoped properties (optional override parameters)
- No separate `Overrides` struct is generated in the current architecture
- The init body:
  1. Assigns all `.input` properties to generated storage
  2. Resolves `.shared` properties with `override ?? factory`
  3. Stores `.transient` overrides for accessor-time usage

**@Provide** scope semantics:
- `.shared`: Singleton-like dependencies created by factory in init (requires `factory:` parameter)
- `.input`: Dependencies passed as init parameters (must not have `factory:`)
- `.transient`: New instance created on every access (requires `factory:` parameter)
- Protocol-typed dependencies for `.shared`/`.transient` should use explicit existential syntax (`any Protocol`)
- Concrete dependency types require `concrete: true` opt-in

### Dependency Graph Generation Flow (CLI)

1. **Container Discovery**: `ContainerCollector` walks all Swift files to find `@DIContainer` types and extract their required `.input` properties and relationships
2. **Usage Analysis**: `ContainerUsageCollector` finds all container initialization calls and records:
   - Which labels were passed (for dependency mapping)
   - Container-to-container edges (for graph visualization)
3. **Graph Generation**:
   - Builds dependency graph from container relationships
   - Outputs in specified format (Mermaid, DOT, ASCII, or PNG via Graphviz)

## Key Design Patterns

### Centralized Parsing
All attribute parsing logic lives in `InnoDICore` to ensure macros and CLI interpret `@Provide` and `@DIContainer` identically. When adding new macro parameters, update both the parsing functions and the macro expansion logic.

### SwiftSyntaxBuilder Usage
Macros prefer `SwiftSyntaxBuilder` APIs over string concatenation for AST generation. This provides type safety and correct formatting. See `makeInitDecl()` for examples.

### Access Level Propagation
The generated `init` inherits the access level of the container type (public, internal, fileprivate, private) via `containerAccessLevel()`.

## Common Development Tasks

When modifying macro behavior:
1. Update parsing logic in `InnoDICore/Parsing.swift` first
2. Update macro expansion in `InnoDIMacros/DIContainerMacro.swift`
3. Add test cases to `Tests/InnoDIMacrosTests/`
4. Consider CLI implications in `Sources/InnoDI-DependencyGraph/` modules (`Collectors`, `Rendering`, `Output`, `CLI`)

When adding diagnostics:
- Use `SimpleDiagnostic` for error messages
- Attach diagnostics to the relevant syntax node for precise error location
- Follow existing patterns: `context.diagnose(Diagnostic(node:message:))`

### Same-file extension 검출 테스트 제약

`DIContainerParser.sourceFile(containing:)`는 대상 decl의 parent chain을 거슬러
올라가 `SourceFileSyntax`를 찾아 같은 파일 내 형제 extension의 `init`을 수집한다.
그러나 `SwiftSyntaxMacroExpansion.expand()` 파이프라인
(`Tests/TestSupport/MacroAssertions.swift`의 `assertMacroExpansion*` 헬퍼들이
내부적으로 사용)은 확장 대상 decl을 parent에서 detach하므로 이 walk가 `nil`을
반환하고 형제 extension init이 수집되지 않는다.

따라서 sibling extension init 검출이 필요한 테스트(예:
`customInitInsideSameFileExtensionIsRejected`,
`allOffendingInitializersAreDiagnosed`,
`nestedSameFileExtensionInitializersAreRejected`)는 `Parser.parse` +
`DIContainerMacro.expansion(of:providingMembersOf:in:)`을 직접 호출하는
기존 패턴을 유지한다. 이 패턴에서는 `context.diagnostics`의 `diagnosticID`를
직접 확인해 code 기반 검증을 유지할 수 있다.

### SwiftSyntaxBuilder 리팩토링 워크플로우

문자열 interpolation(`DeclSyntax = "let \(raw: x) = ..."` 류)으로 생성하던
매크로 출력을 `SwiftSyntaxBuilder` AST 조립으로 전환할 때의 표준 절차:

1. **안전망 확인**: 대상 매크로 출력을 덮는 스냅샷이
   `Tests/InnoDIMacrosTests/__Snapshots__/`에 있는지 확인. 없으면 먼저
   `assertMacroExpansionSnapshot`으로 테스트를 추가한 뒤
   `Tools/record-macro-snapshots.sh`로 기록.
2. **기본 원칙**: 빌더 전환의 성공 기준은 **스냅샷이 변하지 않는 것**이다.
   동일한 출력 문자열을 AST로 다시 만들 수 있으면 회귀가 없다는 뜻.
3. 문자열 interpolation 한 곳을 `VariableDeclSyntax` / `FunctionCallExprSyntax` /
   `ClosureExprSyntax` / `IfExprSyntax` / `AwaitExprSyntax` / `TryExprSyntax`
   등으로 치환 후 `swift test --filter InnoDIMacrosTests` 실행.
4. 스냅샷이 깨지면 diff로 trivia(토큰 전후 공백, 줄바꿈, 키워드 기본 trivia)
   차이를 파악해 AST 조립을 조정. 기존에 `SwiftSyntaxMacroExpansion`이
   자동 포매팅하는 부분과 어긋나면 `trailingTrivia:`/`leadingTrivia:`
   파라미터로 보정.
5. **의도적으로 출력을 바꾼 경우**에만 `Tools/record-macro-snapshots.sh`로
   재기록하고 diff를 커밋/PR에 첨부 — 리뷰어가 의도 변경을 확인할 수 있도록.
   `.gitattributes`의 `linguist-generated=true`로 인해 스냅샷 diff는 기본
   접혀 표시되므로 PR 본문에 요약을 적는 것이 좋다.

참고 사례: [Sources/InnoDIMacros/DIContainerCodeGenerator.swift](Sources/InnoDIMacros/DIContainerCodeGenerator.swift)의
`letBinding(name:value:)` / `makeAsyncTaskDecl(...)` / `dependencyExpression(...)`
헬퍼가 A-phase 빌더 전환의 결과물이다. `Task<S, F> { if let override ... }`
같은 멀티라인 출력도 `GenericSpecializationExprSyntax` + `IfExprSyntax` +
`ClosureExprSyntax` 조합으로 표현 가능하다.
