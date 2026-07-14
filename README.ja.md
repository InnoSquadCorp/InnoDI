# InnoDI

[English](README.md) | [한국어](README.ko.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [简体中文](README.zh-Hans.md) | [日本語](README.ja.md) | [Русский](README.ru.md)

InnoDI は、コンパイル時およびビルド時の検証、依存グラフツール、
階層検証、SwiftUI ヘルパーを備えた Swift 向けのマクロ駆動 DI フレームワークです。

## 最小限の実用例

<!-- innodi:compile -->
```swift
import InnoDI

struct APIClient { let baseURL: String }

@DIContainer
struct AppContainer {
    @Provide(.input) var baseURL: String
    @Provide(.shared, APIClient.self, with: [\AppContainer.baseURL], concrete: true)
    var apiClient: APIClient
}

let client = AppContainer(baseURL: "https://api.example.com").apiClient
```

## InnoDI を使う理由

DI の wiring を明示的かつレビューしやすい形で保ち、失敗をできるだけ早く
見つけたいチーム向けです。

- `@DIContainer` と `@Provide` が、サポート対象の実質的に非ジェネリックな Swift struct からコンテナ API を生成します。
- マクロ検証が展開時にローカルなミスを検出します。
- build validation と graph CLI が、ファイル間、モジュール間、全体グラフの問題を見つけます。
- `InnoDISwiftUI` が root 境界での繰り返し environment wiring を減らします。

InnoDI はランタイムの state machine ではありません。ランタイム状態は
アプリ層や `InnoFlow`、`InnoRouter`、`InnoNetwork` のような補助
フレームワークに置く前提です。
InnoDI は意図的に `@Injected` property wrapper や dynamic registration API
を提供しません。その代わり、明示的な generated initializer、レビュー可能な
wiring、より早い検証を選びます。

## InnoDI を選ぶタイミング

依存関係の wiring を code review で見える形にし、runtime より前に検証し、
graph artifact として調査できるようにしたい場合に InnoDI を選びます。

| 優先したいこと | 候補 | 理由 |
| --- | --- | --- |
| app dependency graph の compile/build-time validation | InnoDI、[SafeDI](https://github.com/dfed/SafeDI)、[Needle](https://github.com/uber/needle) | InnoDI は macro-expanded Swift の container surface、macro diagnostics、build-support checks、DAG CLI を組み合わせます。 |
| runtime registration や late binding | [Swinject](https://github.com/Swinject/Swinject) または [Factory](https://github.com/hmlongco/Factory) | runtime container は動的な登録差し替えが得意です。InnoDI は明示 initializer と早期検証を優先します。 |
| SwiftUI preview と scoped test override | [Factory](https://github.com/hmlongco/Factory)、[swift-dependencies](https://github.com/pointfreeco/swift-dependencies)、または InnoDI | InnoDI は validated app container の上に generated SwiftUI root helpers を置きたい場合に向きます。 |
| hierarchical feature ownership と graph visibility | InnoDI、[Needle](https://github.com/uber/needle)、[SafeDI](https://github.com/dfed/SafeDI) | InnoDI は `@SubContainer` で親子 ownership を表し、graph CLI に ownership edge を出します。 |
| 既存 app への最小導入コスト | [Factory](https://github.com/hmlongco/Factory)、[swift-dependencies](https://github.com/pointfreeco/swift-dependencies)、または incremental InnoDI adoption | InnoDI は container 定義と macro/build validation を受け入れる必要があります。 |

実運用では runtime tool と併用できます。application graph は InnoDI で検証し、
feature 内の局所的な runtime value は `swift-dependencies` や小さな factory
に任せる構成も有効です。

おすすめのレイヤリングは「生成は InnoDI、呼び出し単位の一時 override は
`swift-dependencies`」という分離です。composition root で
`@Dependency(\.date)` などの `DependencyKey` を解決し、その値を container の
`.input` スロットへ渡します。テストは
`withDependencies { $0.date = .constant(...) } operation:` で 1 つの呼び出し
ツリーだけを差し替え、container を作り直したり validated graph を再検証する
必要はありません。InnoDI の container レベル `Overrides` builder は偽の
`APIClient` のようなアプリ全体の差し替えにそのまま使い、
`swift-dependencies` は 1 operation の間だけ有効な override が欲しいときに
取り出します。

## 要件

- Swift tools version `6.2`
- 対応プラットフォーム:
  - iOS 17+
  - macOS 13+
  - watchOS 10+
  - tvOS 17+
  - visionOS 1+

### ビルド時 validator のファイルシステム要件

ビルドプラグインは、Swift Package Manager の scratch ディレクトリ配下で
layered POSIX lock を使って live DAG validation を直列化します。

1. `open(O_CREAT | O_EXCL | O_RDWR)` が単一の lock file を作成します。
2. `flock(LOCK_EX | LOCK_NB)` が descriptor に advisory exclusive lock を追加します。

InnoDI は lock directory の filesystem を自動検出します。APFS、HFS+、
ext4、btrfs、xfs、tmpfs などのローカル filesystem はサポートされます。
NFS mount、SMB/CIFS、WebDAV、FUSE 系 filesystem は、lock atomicity を
信頼できない場合に shared validation cache を壊す可能性があるため、既定で
拒否されます。

ビルドシステムで derived data を shared volume に置く必要がある場合は、
SPM の `--scratch-path` または Xcode の derived-data 位置をローカル
ディレクトリへ向けてください。

```sh
swift build --scratch-path /tmp/innodi-cache
```

plugin は package root の `.build/innodi-dag-validation` には lock/cache state
を作りません。scratch path を移すと validation state も一緒に移動します。

運用者は `INNODI_ALLOW_UNSAFE_LOCK=1` で unsafe-filesystem fail-fast を
迂回できますが、InnoDI は監査可能な警告を出し、リスクはその build
environment に残ります。診断、復旧手順、完全な filesystem 表は
[Lock Safety](Sources/InnoDI/InnoDI.docc/lock-safety.md) を参照してください。

ビルドタイムバリデータは、高速イテレーションや制約された環境向けに 2 つの
opt-out エスケープハッチを提供します。`@DIContainer(validateDAG: false)` は
コンテナ単位、`INNODI_DISABLE_BUILD_VALIDATION=1` はビルドプラグイン全体を
ショートサーキットします。すべての PR は
`Tools/report-validate-dag-escape-hatches.sh` を実行し、これらのエスケープ
ハッチを使用しているサイトをワークフローのステップサマリーに列挙するため、
別途 CI ゲートを設けることなくエスケープハッチの増殖が可視化されます。
プロダクション CI は両方とも unset のままにする必要があります。

## プライバシー

InnoDI は、2 つのランタイムプロダクト `InnoDI` と `InnoDISwiftUI` に Apple
Privacy Manifest (`PrivacyInfo.xcprivacy`) を同梱します。このマニフェストは
ユーザートラッキングなし、トラッキングドメインなし、収集データタイプなし、
Required Reason API 使用なしを宣言します。ビルドタイムツール
(InnoDIBuildSupport、dependency-graph CLI、マクロプラグイン) は利用者のアプリ
に埋め込まれないため、マニフェストには影響しません。iOS、watchOS、tvOS、
visionOS アプリに InnoDI を埋め込む場合、SwiftPM が自動的にマニフェストを
バンドルし、集約プライバシーレポートに表示されます。

## インストール

`Package.swift` に追加します。

```swift
dependencies: [
    .package(url: "https://github.com/InnoSquadCorp/InnoDI.git", from: "4.3.0")
]
```

必要な product を target に追加します。

```swift
.target(
    name: "YourApp",
    dependencies: [
        "InnoDI"
    ]
)
```

SwiftUI helper が必要な場合だけ `InnoDISwiftUI` を追加します。

```swift
.target(
    name: "YourApp",
    dependencies: [
        "InnoDI",
        "InnoDISwiftUI"
    ]
)
```

build-time DAG validator を有効にするには、InnoDI container を宣言する
各 target に plugin を追加します。

```swift
.target(
    name: "YourApp",
    dependencies: [
        "InnoDI"
    ],
    plugins: [
        .plugin(name: "InnoDIDAGValidationPlugin", package: "InnoDI")
    ]
)
```

source-tool のコンパイルが導入コストの大部分を占めると計測済みのチーム向けに、
companion package の `InnoDIValidationTools` は任意の prebuilt macOS
validation plugin を提供します。上記の source plugin か prebuilt plugin の
どちらか一方だけを attach し、両方は attach しないでください。unsupported
hosts と local package development では source plugin を使い続けてください。

## クイックスタート

<!-- innodi:compile -->
```swift
import Foundation
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

    @Provide(.shared, APIClient.self, with: [\AppContainer.baseURL])
    var apiClient: any APIClientProtocol
}

let container = AppContainer(baseURL: "https://api.example.com")
_ = container.apiClient
```

名前や構築ロジックが `Type.self` と `with:` だけでは合わない場合は
factory closure を使います。

```swift
@Provide(.shared, factory: { (baseURL: String) in
    APIClient(baseURL: baseURL)
})
var apiClient: any APIClientProtocol
```

## 先に読むドキュメント

1. [Overview](Sources/InnoDI/InnoDI.docc/ja.lproj/Overview.md)
2. [Validation](Sources/InnoDI/InnoDI.docc/ja.lproj/Validation.md)
3. [Policy Boundaries](Sources/InnoDI/InnoDI.docc/ja.lproj/PolicyBoundaries.md)
4. [Anti-Patterns](Sources/InnoDI/InnoDI.docc/AntiPatterns.md)
5. [Module-Wide Init Detection](Sources/InnoDI/InnoDI.docc/ja.lproj/ModuleWideInitDetection.md)
6. [RELEASING.md](RELEASING.md)
7. [ROADMAP.md](ROADMAP.md)

## コア API

### `@DIContainer`

`@DIContainer` は以下を合成します。

1. primary `init(...)`
2. ネストされた `Overrides`
3. `init(<inputs...>, _ applyOverrides: ...)`
4. `sync` / `throws` / `async` / `async throws` の `withOverrides`

ユーザー定義のネスト `Overrides` 型がない限り、サポート対象の各コンテナが
overrides scaffolding を生成します。

`@DIContainer` がサポートするのは、ファイルスコープまたは nominal type 内に
ネストされた、実質的に非ジェネリックな `struct` 宣言だけです。宣言自体にも、
それを囲む宣言にも、ジェネリックパラメータや `where` 句を指定できません。
`class`、`actor`、`enum`、`protocol`、直接アノテーションした `extension`、
extension 内にネストされた struct は拒否されます。関数、クロージャ、
アクセサ、`switch` case など、実行可能またはローカルなコードスコープ内の
宣言も拒否されます。この境界は `@DIComponent` を併用した宣言にも適用されます。
ランタイムまたは型固有の状態は、protocol dependency または
`@Provide(.input)` の背後に移してください。

現在の Swift compiler は、computed-property body 内の型に attached macro を
展開するとき、accessor ancestry を macro context に含めません。この edge case
は build-validation plugin と dependency-graph CLI が source 全体を scan して
拒否します。container を宣言するすべての target に plugin を接続してください。

```swift
@DIContainer(root: Bool = false, validateDAG: Bool = true, mainActor: Bool = false)
```

| パラメータ | 既定値 | 意味 |
|---|---|---|
| `root` | `false` | グラフ描画の入口フラグです。root が存在する場合、Mermaid、DOT、ASCII 出力は root から到達可能なノードとエッジに限定されます。 |
| `validateDAG` | `true` | global DAG validation と、マクロの local cycle および closure/`with:` graph-derived チェックを有効にします。`false` はその範囲のみ無効化し、`factory:` や initializer の raw-expression 参照診断と構造検証は継続します。 |
| `mainActor` | `false` | 依存関係 accessor、生成されるすべての initializer、`Overrides`、convenience initializer・`withOverrides`・child override・component mount で使う `applyOverrides` 関数型、4 つの `withOverrides` operation closure、feature-root helper を `@MainActor` に隔離します。`@DIComponent` を併用すると、生成される `<Container>Dependencies` protocol と `init(dependencies:_:)` も隔離され、専用の `_InnoDIMainActorComponentMountable` protocol に準拠します。このオプションを使わない通常の component は `_InnoDIComponentMountable` を引き続き使用します。メインアクター外から利用するには明示的な actor hop が必要です。UI ルートコンテナ向けです。 |

5.0 の generic component mounting helper は 2 つの marker protocol を区別する
必要があります。通常の component には `_InnoDIComponentMountable` を維持し、
`mainActor: true` component には `_InnoDIMainActorComponentMountable` constraint
と `@MainActor` override closure を持つ `@MainActor` overload を追加してください。

non-`Sendable` な container/component 値は `@MainActor` caller を使うか、同じ
`MainActor.run` block 内で生成して利用し、main actor に保持してください。
direct `await` は `withOverrides` operation result のように、隔離された処理が
`Sendable` な結果を返す場合に適しています。container 自体を actor 外へ安全に
運べるようにするものではありません。

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

1 回の operation だけに override を閉じ込めることもできます。

```swift
let result = try await AppContainer.withOverrides(baseURL: "https://test.example.com") { overrides in
    overrides.apiClient = MockAPIClient()
} operation: { container in
    try await container.apiClient.fetch()
}
```

input-only コンテナも空の builder を生成します。子コンテナが input-only
の場合でも `<name>Overrides` closure はコンパイルでき、no-op として動作します。

## `Lazy<T>` と `Provider<T>`

- `Lazy<T>` は soft edge を作り、cycle detection から外したいときに使います。
- `Provider<T>` は `.transient` 依存に毎回再入するために使います。

```swift
@Provide(.shared, factory: { (service: Lazy<Service>) in
    Consumer(service: service)
}, concrete: true)
var consumer: Consumer
```

```swift
@Provide(.shared, factory: { (requests: Provider<Request>) in
    RequestLogger(requests: requests)
}, concrete: true)
var logger: RequestLogger
```

どちらも意図的に non-`Sendable` です。

## ネストコンテナと階層

`@SubContainer` は親が所有する子コンテナを表します:

```swift
@SubContainer(scope: .shared, with: [\.config, \.apiClient])
var feature: FeatureContainer
```

主なルール:

- `scope:` は必須です。
- 親の `@Provide` 候補が 0 個または 1 個の場合のみ、名前ベースの
  implicit wiring が convenience として有効です。親候補が複数ある場合は
  生成された Swift initializer のエラーに頼らず、必ず explicit wiring を
  追加してください。
- `with:` は同名の明示 subset / 順序を転送します。マクロが読み取れる
  key path リテラル配列でなければならず、ランタイム変数や計算された
  配列要素はサポートされません。
- `with: []` は明示的な空 subset で、`Child()` を呼び出します。
- `bindings:` は子 input label を別の親メンバー名に remap します。
- `with:`、`bindings:` の wiring form は 1 つだけ選びます。
- 親の `Overrides` には完全置換スロット (`feature`) と子 override closure
  (`featureOverrides`) の両方が追加されます。

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
