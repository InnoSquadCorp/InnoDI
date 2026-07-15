# 統合ガイド

InnoDI は generated Swift source と build-time validation を組み合わせて使います。
多くのツールは、macro output を compiler-generated implementation detail として扱い、
ユーザーが書いた container 宣言を review surface として残すと最も扱いやすくなります。

## Periphery

- hand-written source glob ではなく generated build settings に対して Periphery を実行し、
  macro-expanded member が compiler から見えるようにします。
- `@DIContainer`、`@Provide`、`@SubContainer`、generated override entry point が
  reflection-free wiring からしか呼ばれない場合は、tests、sample apps、または explicit
  retention rules で reachable にします。
- generated-member noise はモジュール全体を ignore するのではなく、container type や
  public entry point を retain して抑えるのが望ましいです。

## SwiftLint

- user-authored source は通常どおり lint します。
- macro-expanded output を hand-written code として lint しないでください。
- generated interface artifact を検査する設定では、InnoDI の reserved generated prefix を
  除外します: `_storage_`, `_override_`, `_innoDI`, `_InnoDI`.

## SwiftFormat

- 自分で書いた container declaration を format 対象にします。
- consumer project で macro expansion snapshot に別の formatting pass を要求しないでください。
- attribute と factory closure は宣言箇所で読みやすく保ちます。そこが reviewer が確認すべき
  source surface です。

## マクロ生成メンバー

InnoDI は container declaration から initializer、storage、override、helper closure を生成します。
generated member は compiled API surface の一部として扱いつつ、manual dependency は source
container に明示的に残します。

ツールが generated symbol を報告した場合は、actionable か判断する前に最も近い
`@DIContainer`、`@Provide`、`@SubContainer` 宣言へ対応づけます。

## ビルドプラグイン

container または standalone `@DIEnvironmentBridge` を宣言する各 target に
`InnoDIDAGValidationPlugin` を付けます。target-scoped full-source pass は attached
macro から見えない enclosing declaration や同じ target の generated qualifier
shadow、import 済み dependency target で可視な `public` / `package` qualifier
shadow を拒否し、bridge の direct-extension attachment と standalone local target
も Swift compile 前に遮断します。

class bridge、または class 内に nested された container/bridge では、preflight は
最初の inherited type を superclass 候補として追跡します。追跡する class と
typealias はすべて workspace snapshot で source-visible である必要があります。
SDK または binary にしか存在しない、unresolved、あるいは ambiguous な最初の
inherited type は `generated-qualifier.inheritance-unverifiable` で拒否されます。
外部 hierarchy を index できない場合は struct/enum または source-visible adapter
を使用してください。保守的な syntax-only index は bridge 生成で使う inherited
type member `Swift` と `SwiftUI` を拒否しますが、inherited `InnoDISwiftUI` は
許可します。direct または enclosing scope の `InnoDISwiftUI` declaration は
引き続き予約されています。

plugin は build coordinator 経由で DAG validator
を in-process 実行するようになりました。standalone
`InnoDI-DependencyGraph` executable は local inspection と CI artifact 用に引き続き利用できます。

derived data が network volume にある場合は local SwiftPM scratch path を使います。scratch path は
local disk 上の writable な場所である必要があります。`/tmp` は OS や CI 環境に応じた local
temporary directory に置き換えてください。

```sh
swift build --scratch-path /tmp/innodi-cache
```

filesystem classification と lock recovery は <doc:lock-safety> を参照してください。
