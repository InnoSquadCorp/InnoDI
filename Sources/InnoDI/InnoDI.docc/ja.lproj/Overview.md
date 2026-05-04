# ``InnoDI``

多層検証を備えた Swift 向けマクロ駆動 DI です。

## Overview

InnoDI は `@DIContainer` と `@Provide` を使って通常の Swift 型を DI
コンテナに変換します。重点は明示的な wiring、決定的な検証、グラフ
ツールにあります。

4.0.0 の stable baseline:

- マクロ生成コンテナ API
- コンパイル時とビルド時の検証
- 全体グラフ描画と DAG 検証
- `Lazy<T>` と `Provider<T>`
- `@SubContainer`、`@DIComponent`、`@DIHierarchyRoot`
- `InnoDISwiftUI` の SwiftUI helper

4.1.0 はこの baseline に release hardening を追加します。

- validation coordinator lock の unsafe filesystem fail-fast
- サポート対象 filesystem での `O_CREAT | O_EXCL` と `flock` の layered lock
- macro-synthesized `fatalError` accessor の代わりになる build-time diagnostic
- strict concurrency と macro-source `fatalError` allow-list を強制する PR/release gate
- stacked peer macro でない `withNames:` 使用向けの `@SubContainer` key-path guidance

## Topics

### Start Here

- <doc:Validation>
- <doc:PolicyBoundaries>
- <doc:IntegrationGuide>
- <doc:ModuleWideInitDetection>
- <doc:DiagnosticsGuide>

### Operations

- <doc:lock-safety>
- <doc:MigrationGuide>

### Container API

- <doc:DIContainer>
- <doc:Provide>
- ``DIComponent()``
- ``DIHierarchyRoot()``
