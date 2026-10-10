# InnoDI

[English](README.md) | [한국어](README.ko.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [简体中文](README.zh-Hans.md) | [日本語](README.ja.md) | [Русский](README.ru.md)

<!-- innodi:guide version=7.0.1 -->
## バージョンと対象範囲

このページは **InnoDI 7.0.1 の簡潔な日本語ユーザーガイド**です。マクロによる依存性注入、コンパイル時・ビルド時検証、依存グラフ、SwiftUI 連携の導入手順をまとめています。動的登録 API や `@Injected` プロパティラッパーは提供しません。

完全な説明の基準は [英語 README](README.md) です。[韓国語 README](README.ko.md) と [韓国語 DocC](Sources/InnoDI/InnoDI.docc/ko.lproj/Overview.md) も利用できます。以下の詳細ガイドへのリンクは原則として英語です。このページの更新は、DocC 全体の日本語訳が提供されていることを意味しません。リリース時点の内容は [7.0.1 タグのドキュメント](https://github.com/InnoSquadCorp/InnoDI/blob/7.0.1/README.md) を参照してください。

<!-- innodi:section requirements -->
## 動作要件と互換性

- Swift 6.2 以上（パッケージの tools version は `6.2`）
- iOS 17+、macOS 14+、watchOS 10+、tvOS 17+、visionOS 1+
- **Apple プラットフォームのみ対応**。Linux は CI のビルド・テスト対象外で、`InnoDITesting` は Apple の `os` モジュールを無条件にインポートします
- `swift-syntax` は厳密に `604.0.0` に固定されています。`509.0.0..<604.0.0` を要求する Mockable 0.6.4 とは同じ SwiftPM 依存グラフで解決できません。[7.0.1 の更新手順](CHANGELOG.md#701) を確認してください
- 検証プラグインのロックとキャッシュに使う SwiftPM scratch ディレクトリには、APFS などのローカルファイルシステムが必要です。NFS、SMB、WebDAV、FUSE は既定で拒否されます。[ロックの安全性](Sources/InnoDI/InnoDI.docc/lock-safety.md)

<!-- innodi:section installation -->
## インストール

### 1. パッケージとプロダクトを追加する

`Package.swift` に依存を追加します。

```swift
dependencies: [
    .package(url: "https://github.com/InnoSquadCorp/InnoDI.git", from: "7.0.1")
]
```


必須のコアは `InnoDI` です。SwiftUI 連携には `InnoDISwiftUI` を追加します。生成モックやオーバーライドプリセットを使うテスト・プレビュー支援ターゲットに限って `InnoDITesting` を追加してください。`InnoDISwiftUI` を使うファイルでは、生成コードだけが SwiftUI を参照する場合も含め、`import SwiftUI` を明示します。

### 2. 必須の検証プラグインを設定する

InnoDI コンテナ、または単独の `@DIEnvironmentBridge` を宣言する**すべてのターゲット**に `InnoDIDAGValidationPlugin` を設定します。

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "InnoDI", package: "InnoDI")
    ],
    plugins: [
        .plugin(name: "InnoDIDAGValidationPlugin", package: "InnoDI")
    ]
)
```

プラグインは正しさを保証する仕組みの一部です。マクロ単体では見えない別ファイルの初期化子、名前の衝突、グローバルな依存グラフなどをビルド時に検証します。Xcode・Tuist の設定と制約は [Integration Guide](Sources/InnoDI/InnoDI.docc/IntegrationGuide.md#build-plugin) を参照してください。`validateDAG: false` と `INNODI_DISABLE_BUILD_VALIDATION=1` は回避手段であり、通常のインストール手順ではありません。本番用 CI では検証を無効にしないでください。[無効化の範囲と制約](Sources/InnoDI/InnoDI.docc/PluginOptOut.md)

<!-- innodi:section quickstart -->
## 最小構成の例

上記の設定後、同じサービスを通常の値とテスト用の値で構築できます。コードは英語版の最小例と同一です。

ターゲットの既定の分離が MainActor の場合、コンテナに `@MainActor` または `nonisolated` を明示してください。マクロはこのビルド設定を推測できません。[分離境界の説明](Sources/InnoDI/InnoDI.docc/DIContainer.md#targets-with-default-mainactor-isolation)

<!-- innodi:compile -->
```swift
import InnoDI

struct APIClient { let baseURL: String }

@DIContainer
struct AppContainer {
    @Input var baseURL: String
    @Provide(.shared, APIClient.self, with: [\Self.baseURL])
    var apiClient: APIClient
}

let live = AppContainer(baseURL: "https://api.example.com")
let test = AppContainer(baseURL: "https://api.example.com") {
    $0.apiClient = APIClient(baseURL: "https://test.example.com")
}
precondition(live.apiClient.baseURL == "https://api.example.com")
precondition(test.apiClient.baseURL == "https://test.example.com")
```

<!-- innodi:section api -->
## API の選び方

| やりたいこと | 使用する API と注意点 |
| --- | --- |
| 外部で作った値を渡す | `@Input`。初期化時に渡し、ファクトリーや `with:` は指定しません |
| サービスを共有する | `@Provide(.shared, ...)`。同じコンテナ内で再利用します |
| アクセスごとに生成する | `@Provide(.transient, ...)`。結果をキャッシュしません |
| 同期サービスを初回アクセスまで作らない | `.shared` に `initialization: .onDemand`。コンテナのコピーは同じ論理キャッシュを共有し、別々の初期化は独立します |
| 型と依存先を明示して構築する | `Type.self` と `with: [\Self.member]`。直接の同期メンバーのみを指定します |
| 独自の構築処理や非同期処理を書く | `factory:` / `asyncFactory:`。同じコンテナ内の依存はルートクロージャーの引数名で宣言します |
| 同期依存の解決を遅らせる | `Lazy<T>` / `Provider<T>`。非同期プロバイダーは対象外で、`Provider<T>` は同期の transient が対象です |
| 子コンテナや実行時引数を持つ子を作る | `@SubContainer` / `@SubContainerFactory`。[階層構造](README.md#nested-containers-and-hierarchy) |
| 非同期サービスの準備・再試行・終了を管理する | `@DIContainer(generateOwned: true)`。[所有コンテナ](Sources/InnoDI/InnoDI.docc/OwnedContainers.md) |
| SwiftUI のルートで依存を渡す | `InnoDISwiftUI` と生成ヘルパー。[SwiftUI 連携](README.md#swiftui-helpers) |

コンテナは対応する、実質的に非ジェネリックな `struct` で宣言します。`@Provide` はその直接の通常の格納 `var` に付けます。構築元（`factory:`、`asyncFactory:`、`Type.self`、プロパティ初期値）は同時に指定できません。クロージャーの依存解決は名前に厳密で、依存先から `async` / `throws` が自動推論されるわけではありません。[宣言とエフェクトの制約](Sources/InnoDI/InnoDI.docc/Provide.md)

<!-- innodi:section lifecycle -->
## 非同期ライフサイクル：準備完了と終了

- `makeOwned` の完了は**準備完了ではありません**。eager な非同期プロバイダーを開始可能な状態にしますが、値がそろうまで待ちません
- `prepare` のレポートを使う場合は `report.isReady` を確認します。`requireReady` は未準備ならスローし、所有者を閉じません。`withPrepared` は選択した依存グラフの準備が完了した場合だけ処理を実行し、成功・失敗のどちらでも終了前に `close()` を待ちます
- 選択していない独立した eager プロバイダーの健全性まで保証されるわけではありません。`retryAndRequireReady` は明示的な再試行を 1 回行う API で、自動再試行ループや更新処理ではありません
- `prepare` の待機タスクをキャンセルしても、プロバイダー自体の処理は続く場合があります。終了は明示的に `await owner.close()` で行います。スコープを抜けるだけでは自動終了しません
- `close()` は生成された非同期スコープを閉じ、その後の非同期読み取りを拒否します。キャンセルを無視するファクトリーの完了までは待ちません。返却済みサービスの `shutdown()` を呼んだり、返却済みの値を無効化したり、アプリ独自のタスクを終了したりはしません。同期値、入力、通常の子コンテナは借用された値として残ります
- 所有 API を使わない通常の eager な非同期 shared プロバイダーはコンテナ初期化時に開始し、コンテナはそのタスクをキャンセルしません。`.onDemand` の非同期 shared は読み取りまで開始せず、そのアクセサーは常に throwing です。生成される `closeAsyncProviders()` の契約は [非同期 shared の寿命](Sources/InnoDI/InnoDI.docc/Provide.md#asynchronous-shared-lifetime) を参照してください

詳細は [Owned Containers](Sources/InnoDI/InnoDI.docc/OwnedContainers.md) と [Async Preparation](Sources/InnoDI/InnoDI.docc/AsyncPreparation.md) を参照してください。`close()` をアプリ全体の終了保証として扱わないでください。

<!-- innodi:section testing -->
## テスト、オーバーライド、プレビュー

最小例の `Overrides` ビルダーで、実サービスをテスト用の値に置き換えられます。1 回の処理に適用するなら `withOverrides`、所有コンテナをプリセットで作るなら `makeOwnedWithOverrides` を使います。後者は自動で準備や終了を行いません。非同期値のオーバーライドはファクトリーを実行せず ready なスコープを作りますが、宣言されたグラフ全体の検証は省略されません。

`@GenerateMock` は**実験的なオプトイン API**です。生成形式は変更される可能性があります。`InnoDITesting` のスタブ検証、呼び出し記録、世代を考慮したリセット、型付きプリセットは [Auto Mock](Sources/InnoDI/InnoDI.docc/AutoMock.md) と [テスト支援 API](Sources/InnoDITesting/InnoDITesting.docc/InnoDITesting.md) を参照してください。プレビューには [SwiftUI Preview Helper](Sources/InnoDI/InnoDI.docc/SwiftUIPreviewHelper.md) が役立ちます。

<!-- innodi:section diagnostics -->
## 診断と移行コマンド

以下はツールを実行できる InnoDI リポジトリのチェックアウトで実行し、`/path/to/consumer` を対象プロジェクトのパスに置き換えてください。最初は読み取り専用の診断と移行チェックから始めます。

```bash
swift run InnoDI-Doctor --root /path/to/consumer
swift run InnoDI-Doctor --root /path/to/consumer --json
swift run InnoDI-DependencyGraph --root /path/to/consumer --root-pruning all
swift run InnoDI-DependencyGraph --root /path/to/consumer --validate-dag
swift run InnoDI-Migrate --root /path/to/consumer --check
swift run InnoDI-Migrate --root /path/to/consumer --report --output migration-report.json
```

Doctor の既定の解析処理は依存解決、ビルド、ソース変更、キャッシュ削除、プロセス停止を行いません。ただし、起動に使う `swift run` 自体がツールをビルドすることはあります。動的な Package.swift や Tuist のターゲット対応が解析できない場合は、完全な検証済みとは扱いません。移行レポートはソース本文を含まず、終了コードは `0`（変更不要）、`1`（変更が必要）、`2`（阻害要因あり）です。

変更内容を確認してから、書き込みモードを実行します。

```bash
swift run InnoDI-Migrate --root /path/to/consumer --write
```

6.x からは親キー・パスを `\Self.member` に統一し、必要な `import SwiftUI` を追加し、macOS の最小バージョンを 14 に上げます。型付き prewarm と所有ライフサイクルの移行は自動化されていません。置き換え前のファイルが `RECOVERY` パスに残った場合は確認してから削除し、変更後は利用側の通常の設定でビルド・テストしてください。[移行ガイド](Sources/InnoDI/InnoDI.docc/MigrationGuide.md#6x--70)

<!-- innodi:section documentation -->
## 目的別の詳細ガイド

| 目的 | 詳細ドキュメント（英語） |
| --- | --- |
| 全体像と最初のコンテナ | [Overview](Sources/InnoDI/InnoDI.docc/Overview.md)、[Hello](Sources/InnoDI/InnoDI.docc/Tutorial-01-Hello.md) |
| 入力、結線、具象型、子コンテナを順に学ぶ | [Inputs](Sources/InnoDI/InnoDI.docc/Tutorial-02-Inputs.md)、[Wiring](Sources/InnoDI/InnoDI.docc/Tutorial-03-Wiring.md)、[Concrete](Sources/InnoDI/InnoDI.docc/Tutorial-04-Concrete.md)、[SubContainer](Sources/InnoDI/InnoDI.docc/Tutorial-05-SubContainer.md) |
| 生成 API、分離、依存順序 | [DIContainer](Sources/InnoDI/InnoDI.docc/DIContainer.md)、[依存順序](Sources/InnoDI/InnoDI.docc/DIContainer.md#opt-in-dependency-ordering) |
| スコープ、ファクトリー、エフェクト、prewarm | [Provide](Sources/InnoDI/InnoDI.docc/Provide.md)、[Lazy / Provider](README.md#lazyt-and-providert) |
| 非同期準備、再試行、終了 | [Owned Containers](Sources/InnoDI/InnoDI.docc/OwnedContainers.md)、[Async Preparation](Sources/InnoDI/InnoDI.docc/AsyncPreparation.md) |
| 階層、assisted factory、コレクション | [階層構造](README.md#nested-containers-and-hierarchy)、[コレクション構成](README.md#collection-composition) |
| SwiftUI、プレビュー、テスト | [SwiftUI Helpers](README.md#swiftui-helpers)、[Preview Helper](Sources/InnoDI/InnoDI.docc/SwiftUIPreviewHelper.md)、[Auto Mock](Sources/InnoDI/InnoDI.docc/AutoMock.md)、[InnoDITesting](Sources/InnoDITesting/InnoDITesting.docc/InnoDITesting.md) |
| プラグイン設定と検証境界 | [Integration](Sources/InnoDI/InnoDI.docc/IntegrationGuide.md)、[Validation](Sources/InnoDI/InnoDI.docc/Validation.md)、[DAG Validation](Sources/InnoDI/InnoDI.docc/DAGValidation.md)、[初期化子検出](Sources/InnoDI/InnoDI.docc/ModuleWideInitDetection.md) |
| 診断、例外設定、ロック障害 | [Diagnostics](Sources/InnoDI/InnoDI.docc/DiagnosticsGuide.md)、[Policy Boundaries](Sources/InnoDI/InnoDI.docc/PolicyBoundaries.md)、[Plugin Opt-Out](Sources/InnoDI/InnoDI.docc/PluginOptOut.md)、[Lock Safety](Sources/InnoDI/InnoDI.docc/lock-safety.md)、[Anti-Patterns](Sources/InnoDI/InnoDI.docc/AntiPatterns.md) |
| グラフ、CI 契約差分、実行時トレース | [CLI](README.md#cli-and-release-surface)、[Runtime Tracing](Sources/InnoDI/InnoDI.docc/RuntimeTracing.md)、[CI 運用方針](docs/automation-policy.md) |
| アップグレード、他の DI からの移行 | [Migration Guide](Sources/InnoDI/InnoDI.docc/MigrationGuide.md)、[Factory から](Sources/InnoDI/InnoDI.docc/MigratingFromFactory.md)、[Swinject から](Sources/InnoDI/InnoDI.docc/MigratingFromSwinject.md)、[CHANGELOG](CHANGELOG.md) |
| 実装例とプライバシー | [Examples](Examples)、[Privacy](README.md#privacy) |

[全体の案内と構成](Sources/InnoDI/InnoDI.docc/DocumentationGuide.md) · [Assisted Factory / Collection](Sources/InnoDI/InnoDI.docc/Composition.md) · [InnoDITesting API](Sources/InnoDITesting/InnoDITesting.docc/InnoDITesting.md)

<!-- innodi:section history -->
## 過去のドキュメント

[6.0.0 時点の日本語 README](https://github.com/InnoSquadCorp/InnoDI/blob/6.0.0/README.ja.md) は過去バージョンの資料です。7.0.1 の導入手順とは区別して参照してください。
