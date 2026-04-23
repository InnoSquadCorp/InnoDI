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

## Topics

### Start Here

- <doc:Validation>
- <doc:PolicyBoundaries>
- <doc:ModuleWideInitDetection>

### Container API

- <doc:DIContainer>
- <doc:Provide>
- ``DIComponent()``
- ``DIHierarchyRoot()``
