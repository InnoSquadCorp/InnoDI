# SwiftUI Preview Helper

`#PreviewWithContainer` lives in `InnoDISwiftUI` and wraps Xcode 16's
`#Preview` so a preview body declares its container once instead of repeating
local setup code.

Use it when a SwiftUI feature root already comes from an InnoDI container and
the preview should exercise the same generated accessor that production code
uses. Keep the preview container local to the preview source file so override
state does not leak across unrelated previews.

See `Examples/PreviewInjectionExample/Sources/PreviewInjectionExample/main.swift`
for live, preview, and failure scenarios after migration.
