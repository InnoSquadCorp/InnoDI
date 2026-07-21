import Foundation
import Testing

@Suite("Coverage floor contracts")
struct CoverageFloorContractTests {
    @Test("Checked-in floors cover every production module")
    func checkedInFloorCoversProductionModules() throws {
        let root = packageRootURL()
        let payload = try #require(
            JSONSerialization.jsonObject(
                with: Data(
                    contentsOf: root.appendingPathComponent(
                        "Tools/coverage-floor.json"
                    )
                )
            ) as? [String: Any]
        )
        let modules = try #require(payload["modules"] as? [String: Double])

        #expect(payload["schemaVersion"] as? Int == 1)
        #expect(Set(modules.keys) == [
            "InnoDI",
            "InnoDI-DependencyGraph",
            "InnoDI-Migrate",
            "InnoDIBuildSupport",
            "InnoDICore",
            "InnoDIDependencyGraphCLI",
            "InnoDIDependencyGraphCore",
            "InnoDIMacros",
            "InnoDIMigrationCore",
            "InnoDISwiftUI",
            "InnoDIWorkspaceAnalysis",
        ])

        let macroWorkflow = try String(
            contentsOf: root.appendingPathComponent(
                ".github/workflows/macro-tests.yml"
            ),
            encoding: .utf8
        )
        let releaseWorkflow = try String(
            contentsOf: root.appendingPathComponent(
                ".github/workflows/release.yml"
            ),
            encoding: .utf8
        )
        #expect(macroWorkflow.contains("Tools/check-coverage-floor.py"))
        #expect(releaseWorkflow.contains("Tools/check-coverage-floor.py"))
        #expect(releaseWorkflow.contains("--enable-code-coverage"))
    }

    @Test("Checker accepts floors and rejects module regressions")
    func checkerFailsClosed() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "InnoDI-CoverageFloor-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let floorURL = root.appendingPathComponent("floor.json")
        let summaryURL = root.appendingPathComponent("summary.json")
        try writeCoverageJSON([
            "schemaVersion": 1,
            "packageLinePercent": 89.0,
            "modules": ["Example": 79.0],
        ], to: floorURL)
        try writeCoverageJSON(
            coverageSummary(moduleCovered: 80),
            to: summaryURL
        )

        let passing = try runCoverageFloorCheck(
            floorURL: floorURL,
            summaryURL: summaryURL
        )
        #expect(passing.exitCode == 0)
        #expect(passing.output.contains("Coverage floors: OK"))

        try writeCoverageJSON(
            coverageSummary(moduleCovered: 78),
            to: summaryURL
        )
        let failing = try runCoverageFloorCheck(
            floorURL: floorURL,
            summaryURL: summaryURL
        )
        #expect(failing.exitCode == 1)
        #expect(
            failing.output.contains(
                "module Example line coverage 78.00% is below 79.00%"
            )
        )
    }
}

private struct CoverageFloorCommandResult {
    let exitCode: Int32
    let output: String
}

private func coverageSummary(moduleCovered: Int) -> [String: Any] {
    [
        "package": [
            "linesCovered": 90,
            "linesTotal": 100,
            "linePercent": 90.0,
        ],
        "modules": [[
            "name": "Example",
            "linesCovered": moduleCovered,
            "linesTotal": 100,
            "linePercent": Double(moduleCovered),
        ]],
    ]
}

private func writeCoverageJSON(
    _ value: [String: Any],
    to url: URL
) throws {
    try JSONSerialization.data(
        withJSONObject: value,
        options: [.prettyPrinted, .sortedKeys]
    ).write(to: url)
}

private func runCoverageFloorCheck(
    floorURL: URL,
    summaryURL: URL
) throws -> CoverageFloorCommandResult {
    let outputURL = floorURL.deletingLastPathComponent()
        .appendingPathComponent("output-\(UUID().uuidString).log")
    _ = FileManager.default.createFile(
        atPath: outputURL.path,
        contents: nil
    )
    let output = try FileHandle(forWritingTo: outputURL)
    defer {
        try? output.close()
        try? FileManager.default.removeItem(at: outputURL)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = [
        packageRootURL()
            .appendingPathComponent("Tools/check-coverage-floor.py")
            .path,
        "--floor", floorURL.path,
        "--summary", summaryURL.path,
    ]
    process.standardOutput = output
    process.standardError = output
    try process.run()
    process.waitUntilExit()
    try output.synchronize()

    return CoverageFloorCommandResult(
        exitCode: process.terminationStatus,
        output: try String(contentsOf: outputURL, encoding: .utf8)
    )
}
