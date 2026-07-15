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
    @Provide(.shared, APIClient.self, with: [\Self.baseURL])
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

- Swift tools version `6.2` (CI 検証: Swift 6.2 / 6.3)
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

    @Provide(.shared, APIClient.self, with: [\Self.baseURL])
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

管理対象メンバーがない場合も含め、すべてのコンテナが完全な overrides
scaffolding を生成します。ユーザー定義のネスト `Overrides` 型は InnoDI 5.0
ではサポートされず、`container.overrides-name-conflict` が発生します。mount
可能な override ABI を macro が所有できるよう、その宣言を改名してください。

macro は親コンテナの生成 mount code 用に、予約済み compiler-support alias
`_InnoDIMountOverrides = Overrides` も生成します。この underscore 名を直接宣言・
参照しないでください。

コンテナのすべての stored instance member には `@Provide` または
`@SubContainer` が必要です。computed/static property は引き続き使用できます。
これにより生成 initializer が全状態を所有し、memberwise initializer の ABI
drift を防ぎます。

`@DIContainer` がサポートするのは、ファイルスコープまたは nominal type 内に
ネストされた、実質的に非ジェネリックな `struct` 宣言だけです。宣言自体にも、
それを囲む宣言にも、ジェネリックパラメータや `where` 句を指定できません。
`class`、`actor`、`enum`、`protocol`、直接アノテーションした `extension`、
extension 内にネストされた struct は拒否されます。関数、クロージャ、
アクセサ、`switch` case など、実行可能またはローカルなコードスコープ内の
宣言も拒否されます。この境界は `@DIComponent` を併用した宣言にも適用されます。
ランタイムまたは型固有の状態は、protocol dependency または
`@Provide(.input)` の背後に移してください。

明示的な `private` container も、sibling container が生成 mount surface に
アクセスできないため拒否されます。同一 file 内の mount には `fileprivate`、
または private namespace 内の default-access container を使用してください。

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
| `validateDAG` | `true` | global DAG validation とマクロの local graph-derived チェックを有効にします。`false` は global DAG と local cycle を無効化しますが、宣言検証と明示的な sibling edge の effect compatibility は継続します。 |
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

InnoDI 5.0 では、`@Provide` は `@DIContainer` を付与した同じ supported struct
の direct かつ plain な stored instance `var` にのみ指定できます。`let`、
computed/observed property、`lazy`、`weak`、`unowned`、`static`/`class`、
standalone、間接的な nested usage は拒否されます。生成される provider accessor
は InnoDI が所有するため、`_InnoDIProvideAccessor` を手動で付与しないでください。

Provider declaration の attribute と access control も closed contract です。
Property wrapper、conditional/unknown attribute、`private(set)` などの setter
access modifier、custom global-actor attribute は拒否されます。`@Provide` 以外の
source-written property-level attribute は許可されず、`@MainActor` も含まれます。
actor isolation は `@DIContainer(mainActor: true)` で指定してください。provider
declaration と accessor に InnoDI が生成する isolation attribute は internal
compiler support です。完全な `@Provide` member declaration を `#if` 内に置く形も
`provide.conditional-declaration-unsupported` で拒否されます。宣言は条件の外に
置き、factory または注入する実装の内部で分岐してください。

各 property に付与できる `@Provide` は正確に 1 つです。重複 attribute は
`provide.duplicate-attribute` で拒否されます。明示的な property type に opaque
`some Protocol` または implicitly unwrapped optional `T!` は使用できません。
それぞれ `any Protocol`、明示的な `T` または `T?` に移行してください。
compiler-support accessor と別の property wrapper を意図的に偽装して併用した
場合、InnoDI の misuse diagnostic に加えて Swift 自身の structural diagnostic
が発生することがあります。

```swift
@Provide(
    _ scope: DIScope = .shared,
    _ type: Any.Type? = nil,
    with dependencies: [AnyKeyPath] = [],
    factory: Any? = nil,
    asyncFactory: Any? = nil,
    escaping: Bool = false
)
```

| Scope | 意味 | 構築ルール |
|---|---|---|
| `.input` | コンテナ初期化時に外部から渡す依存関係 | `factory:`、`asyncFactory:`、`Type.self`、property initializer、`with:` をすべて宣言しない |
| `.shared` | コンテナ単位で 1 回生成して再利用 | `factory:`、`asyncFactory:`、`Type.self`、property initializer のうち正確に 1 つを宣言 |
| `.transient` | アクセスのたびに再生成 | `factory:`、`asyncFactory:`、`Type.self`、property initializer のうち正確に 1 つを宣言 |

追加ルール:

- `.shared` / `.transient` では `factory:`、`asyncFactory:`、`Type.self`、
  property initializer の 4 つの construction source は相互排他です。
- `.input` はすべての construction source と `with:` を拒否します。
- 生成される `.input` initializer parameter は宣言型 `T` の eager value です。
  Swift は通常どおり initializer call の前に `try` / `await` argument expression
  を評価します。直接記述された non-optional function type は自動検出され、
  escaping parameter として生成されます。non-optional function type が typealias
  の背後にある場合は `@Provide(.input, escaping: true)` を使用してください。
  `escaping:` は literal Bool で、`.input` でのみ有効です。明らかな nonfunction
  / optional-function shape は拒否され、保守的に許可された identifier/member
  alias が実際には non-optional function でない場合、Swift 自身の diagnostic
  が発生することがあります。
- `asyncFactory` は `.shared` と `.transient` で利用でき、`async` closure
  でなければなりません。
- `with:` は `Type.self` construction でのみ利用できます。literal array の
  各要素は `with: [\Self.config]` のように canonical な
  direct-member 表記 `\Self.member` を正確に使う必要があります。`with: []` も
  有効です。named container、module-qualified、typealias root、nested component、
  optional chaining、subscript、computed array element は拒否されます。参照先
  provider はすべて同期 construction でなければなりません。
- 宣言した property type が storage shape を決定します。具象の nominal type は
  具象 storage、`any Protocol` は existential storage になります。
- factory パラメータと `with:` wiring の name 解決は member name に対して厳密です。

Sibling DI edge は次の閉じた構文だけから生成されます。

- root `factory:` / `asyncFactory:` closure literal の named parameter ごとに
  1 本の edge を生成します。nested closure や任意の identifier は edge を
  追加しません。
- `Type.self` は literal canonical `\Self.member` key-path array から edge を
  生成し、同期 provider だけを target にできます。
- closure ではない `factory:` expression と property initializer は opaque な
  zero-edge construction source であり、sibling container member を参照できません。
  DI wiring は root closure parameter へ書き換え、DI edge を意図しない場合は
  qualified global/static construction symbol を使用してください。

Factory effect は明示的に宣言し、依存関係から推論しません。非同期 consumer
には `asyncFactory:` を使い、throwing な非同期 provider を消費する場合は
closure に `async throws` を明記してください。Effect compatibility は
`validateDAG: false` の場合もすべての明示的 edge で検証されます。

| Provider | sync consumer | `async` consumer | `async throws` consumer |
|---|---:|---:|---:|
| sync | 許可 | 許可 | 許可 |
| `async` | 拒否 | 許可 | 許可 |
| `async throws` | 拒否 | 拒否 | 許可 |

`Lazy<T>` と `Provider<T>` は同期 deferred wrapper です。非同期 target は
拒否されます。

## 検証モデル

InnoDI は次の層で検証します。

1. Macro validation
2. Build validation
3. Global DAG validation

`validateDAG: false` は限定的な opt-out です。global DAG validation と local
cycle などの graph-derived チェックのみを無効にします。宣言検証や、root
closure / `with:` が作る明示的 sibling edge の effect compatibility は無効に
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
})
var consumer: Consumer
```

```swift
@Provide(.shared, factory: { (requests: Provider<Request>) in
    RequestLogger(requests: requests)
})
var logger: RequestLogger
```

どちらも意図的に non-`Sendable` です。また同期 wrapper のままであり、
`asyncFactory` member を target にできません。

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
- `@SubContainer(..., featureRoot:)` と `featureRoots:` は、デフォルトまたは
  名前付きの feature-root helper を生成します。
- InnoDI 5.0 では非推奨の互換マクロ `@DIFeatureRoot` を削除します。
  `@SubContainer` の feature-root 引数へ移行してください。

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
