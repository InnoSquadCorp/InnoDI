import Foundation
import Testing

@Suite("Example entrypoint contracts")
struct ExampleEntrypointContractTests {
    @Test("Explicit @main examples avoid the reserved main.swift filename")
    func explicitMainExamplesAvoidReservedMainSwiftFilename() throws {
        let rootURL = packageRootURL()
        let entrypoints = [
            "Examples/SampleApp/App.swift",
            "Examples/SwiftUIExample/Sources/SwiftUIExample/SwiftUIExampleApp.swift",
            "Examples/PreviewInjectionExample/Sources/PreviewInjectionExample/PreviewInjectionExampleApp.swift",
        ]

        for entrypoint in entrypoints {
            let fileURL = rootURL.appendingPathComponent(entrypoint)
            let source = try String(contentsOf: fileURL, encoding: .utf8)

            #expect(
                fileURL.lastPathComponent != "main.swift",
                "\(entrypoint) must not combine @main with Swift's reserved main.swift entrypoint"
            )
            #expect(
                source.contains("@main"),
                "\(entrypoint) must remain an explicit @main entrypoint"
            )
        }
    }
}
