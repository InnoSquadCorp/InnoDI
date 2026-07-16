import Foundation
import Testing

@Suite("Generated qualifier graph CLI preflight")
struct GeneratedQualifierPreflightCLITests {
    @Test("Root-path render and DAG modes reject cross-file qualifier shadows")
    func everyGraphModeRunsFullSourceQualifierValidation() throws {
        let fixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "InnoDI-CLI-Qualifier-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: fixtureURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        try """
        @DIContainer(root: true, mainActor: true)
        struct AppContainer {
            @Provide(.input) var value: Int
        }
        """.write(
            to: fixtureURL.appendingPathComponent("Container.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "struct Swift {}\n".write(
            to: fixtureURL.appendingPathComponent("Shadow.swift"),
            atomically: true,
            encoding: .utf8
        )
        let rootPath = fixtureURL.path(percentEncoded: false)

        for arguments in [
            [
                "--root", rootPath,
                "--root-pruning", "all",
                "--format", "ascii",
            ],
            ["--root", rootPath, "--validate-dag"],
        ] {
            let result = try runCLI(arguments)

            #expect(result.exitCode == 1)
            #expect(result.stdout.isEmpty)
            #expect(
                result.stderr.components(
                    separatedBy: "[container.reserved-module-name]"
                ).count - 1 == 1
            )
            #expect(result.stderr.contains("Declaration 'Swift'"))
            #expect(!result.stdout.contains("DAG validation passed"))
        }
    }
}
