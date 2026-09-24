# ``InnoDI``

多層検証を備えた Swift 向けマクロ駆動 DI です。

## Overview

InnoDI は `@DIContainer` と `@Provide` を使って、ファイルスコープまたは
nominal type 内にネストされた、サポート対象の実質的に非ジェネリックな
Swift struct を DI コンテナに変換します。関数、クロージャ、アクセサ、
`switch` case を含む、実行可能またはローカルなコードスコープ内の宣言は
サポートしません。重点は明示的な wiring、決定的な検証、グラフツールに
あります。

4.0.0 の stable baseline:

- マクロ生成コンテナ API
- コンパイル時とビルド時の検証
- 全体グラフ描画と DAG 検証
- `Lazy<T>` と `Provider<T>`
- `@SubContainer` と明示的な `@DIContainerRole` hierarchy role
- `InnoDISwiftUI` の SwiftUI helper

4.1.0 はこの baseline に release hardening を追加します。

- validation coordinator lock の unsafe filesystem fail-fast
- サポート対象 filesystem での `O_CREAT | O_EXCL` と `flock` の layered lock
- macro-synthesized `fatalError` accessor の代わりになる build-time diagnostic
- strict concurrency と macro-source `fatalError` allow-list を強制する PR/release gate
- `@SubContainer` の same-name wiring は `with:` のみになり、`withNames:` escape hatch は削除されました

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
- ``Input(_:escaping:)``
- ``DIContainerRole(role:mainActor:validateDAG:)``
