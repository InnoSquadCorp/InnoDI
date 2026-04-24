# InnoDI

[English](README.md) | [한국어](README.ko.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [简体中文](README.zh-Hans.md) | [日本語](README.ja.md) | [Русский](README.ru.md)

InnoDI は、コンパイル時およびビルド時の検証、依存グラフツール、
階層検証、SwiftUI ヘルパーを備えた Swift 向けのマクロ駆動 DI フレームワークです。

## InnoDI を使う理由

DI の wiring を明示的かつレビューしやすい形で保ち、失敗をできるだけ早く
見つけたいチーム向けです。

- `@DIContainer` と `@Provide` が通常の Swift 型からコンテナ API を生成します。
- マクロ検証が展開時にローカルなミスを検出します。
- build validation と graph CLI が、ファイル間、モジュール間、全体グラフの問題を見つけます。
- `InnoDISwiftUI` が root 境界での繰り返し environment wiring を減らします。

InnoDI はランタイムの state machine ではありません。ランタイム状態は
アプリ層や `InnoFlow`、`InnoRouter`、`InnoNetwork` のような補助
フレームワークに置く前提です。

## 要件

- Swift tools version `6.2`
- 対応プラットフォーム:
  - iOS 17+
  - macOS 13+
  - watchOS 10+
  - tvOS 17+
  - visionOS 1+

### ビルド時 validator のファイルシステム要件

ビルドプラグインは、Swift Package Manager の derived data ディレクトリ
配下に置いた POSIX `O_CREAT | O_EXCL` ロックファイルで live DAG
validation を直列化します。APFS、HFS+、ext4、btrfs、xfs などのローカル
ファイルシステムでは正しく動作しますが、ネットワーク上のパスには注意が
必要です。

- **NFSv3** は atomic な `O_EXCL` semantics を保証しないため、複数の
  クライアントが同時にロックを作成できたと判断することがあります。
  NFSv4 を使うか、derived data をローカルパスへ移してください。
- **SMB/CIFS** share は信頼できる `O_EXCL` atomicity を提供しないため、
  サポート対象外です。
- **Docker / Kubernetes bind mount** は host filesystem の semantics を
  継承します。host がローカル filesystem であれば安全です。

ビルドシステムで derived data を shared volume に置く必要がある場合は、
プラグインを有効にする前に SPM の `--scratch-path` または Xcode の
derived-data 位置をローカルディレクトリへ向けてください。

## インストール

`Package.swift` に追加します。

```swift
dependencies: [
    .package(url: "https://github.com/InnoSquadCorp/InnoDI.git", from: "4.0.0")
]
```

必要な product を target に追加します。

```swift
.target(
    name: "YourApp",
    dependencies: [
        "InnoDI",
        "InnoDISwiftUI"
    ]
)
```

SwiftUI helper を使わない場合は `InnoDI` だけで十分です。

## クイックスタート

```swift
import InnoDI

protocol APIClientProtocol {
    func fetch() async throws -> Data
}

struct APIClient: APIClientProtocol {
    let baseURL: String
    func fetch() async throws -> Data { Data() }
}

@DIContainer
struct AppContainer {
    @Provide(.input)
    var baseURL: String

    @Provide(.shared, APIClient.self, with: [\.baseURL])
    var apiClient: any APIClientProtocol
}

let container = AppContainer(baseURL: "https://api.example.com")
let client = container.apiClient
```

## 先に読むドキュメント

1. [Overview](Sources/InnoDI/InnoDI.docc/ja.lproj/Overview.md)
2. [Validation](Sources/InnoDI/InnoDI.docc/ja.lproj/Validation.md)
3. [Policy Boundaries](Sources/InnoDI/InnoDI.docc/ja.lproj/PolicyBoundaries.md)
4. [Module-Wide Init Detection](Sources/InnoDI/InnoDI.docc/ja.lproj/ModuleWideInitDetection.md)
5. [RELEASING.md](RELEASING.md)
6. [ROADMAP.md](ROADMAP.md)

## コア API

### `@DIContainer`

`@DIContainer` は以下を合成します。

1. primary `init(...)`
2. ネストされた `Overrides`
3. `init(<inputs...>, _ applyOverrides: ...)`
4. `sync` / `throws` / `async` / `async throws` の `withOverrides`

ユーザー定義のネスト `Overrides` 型がない限り、すべてのコンテナが
overrides scaffolding を生成します。

| パラメータ | 既定値 | 意味 |
|---|---|---|
| `root` | `false` | グラフ描画の入口フラグです。root が存在する場合、Mermaid、DOT、ASCII 出力は root から到達可能なノードとエッジに限定されます。 |
| `validateDAG` | `true` | global DAG validation と、マクロの local cycle および closure/`with:` graph-derived チェックを有効にします。`false` はその範囲のみ無効化し、`factory:` や initializer の raw-expression 参照診断と構造検証は継続します。 |
| `mainActor` | `false` | 生成されるコンテナ API に `@MainActor` を適用します。UI ルート向けです。 |

### `@Provide` とスコープ

```swift
@Provide(
    _ scope: DIScope = .shared,
    _ type: Any.Type? = nil,
    with dependencies: [AnyKeyPath] = [],
    factory: Any? = nil,
    asyncFactory: Any? = nil,
    concrete: Bool = false
)
```

| Scope | 意味 | 構築ルール |
|---|---|---|
| `.input` | コンテナ初期化時に外部から渡す依存関係 | `factory` / `asyncFactory` は不可 |
| `.shared` | コンテナ単位で 1 回生成して再利用 | `factory`、`asyncFactory`、または `Type.self` + `with:` が必要 |
| `.transient` | アクセスのたびに再生成 | `factory`、`asyncFactory`、または `Type.self` + `with:` が必要 |

追加ルール:

- `factory` と `asyncFactory` は相互排他です。
- `asyncFactory` は `async` クロージャである必要があります。
- 具象型の `.shared` / `.transient` ストレージには `concrete: true` が必要です。
- factory パラメータと `with:` wiring の name 解決は member name に対して厳密です。

## 検証モデル

InnoDI は次の層で検証します。

1. Macro validation
2. Build validation
3. Global DAG validation

`validateDAG: false` は限定的な opt-out です。global DAG validation と、
マクロの local cycle / closure-`with:` graph-derived チェックのみを
無効にします。構造検証や raw-expression 参照のコンパイル時診断は無効に
なりません。

## Overrides Builder

生成される `Overrides` builder を使うと、テストで必要なメンバーだけを
差し替えられます。

```swift
let container = AppContainer(baseURL: "https://test.example.com") { overrides in
    overrides.apiClient = MockAPIClient()
}
```

input-only コンテナも空の builder を生成します。子コンテナが input-only
の場合でも `<name>Overrides` closure はコンパイルでき、no-op として動作します。

## `Lazy<T>` と `Provider<T>`

- `Lazy<T>` は soft edge を作り、cycle detection から外したいときに使います。
- `Provider<T>` は `.transient` 依存に毎回再入するために使います。

どちらも意図的に non-`Sendable` です。

## ネストコンテナと階層

`@SubContainer` は親が所有する子コンテナを表します。

- `scope:` は必須です。
- 親の `@Provide` 候補が 0 個または 1 個の場合だけ、名前ベースの
  implicit wiring が convenience として使われます。
- 親候補が複数ある場合は `with:`、`withNames:`、`bindings:` による
  explicit wiring が必要です。
- `with:` または `withNames:` は同名の明示 subset を転送します。
- `bindings:` は子 input label を別の親メンバー名に remap します。
- 親の `Overrides` には完全置換スロットと子 override closure の両方が追加されます。

モジュールをまたぐ ownership には:

- `@DIComponent`
- `@DIHierarchyRoot`

## SwiftUI Helper

`InnoDISwiftUI` は次を提供します。

- `.innodi(container)`
- `@DIEnvironmentBridge`
- `@DIFeatureRoot`

## CLI とリリース情報

```bash
swift run InnoDI-DependencyGraph --root .
swift run InnoDI-DependencyGraph --root . --validate-dag
Tools/generate-docc.sh
```

リリースノートとアップグレードノートは [RELEASING.md](RELEASING.md) にあります。

## サンプル

- [Examples/README.md](Examples/README.md)
- [Examples/SwiftUIExample](Examples/SwiftUIExample)
- [Examples/PreviewInjectionExample](Examples/PreviewInjectionExample)
- [Sources/InnoDIExamples/main.swift](Sources/InnoDIExamples/main.swift)
