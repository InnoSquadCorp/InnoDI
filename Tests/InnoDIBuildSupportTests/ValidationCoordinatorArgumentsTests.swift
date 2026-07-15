import Testing

@testable import InnoDIBuildSupport

@Suite("Validation coordinator arguments")
struct ValidationCoordinatorArgumentsTests {
    @Test("Root input preserves compatibility options")
    func parsesRootInput() throws {
        let arguments = try parseValidationCoordinatorArguments([
            "--root", "/tmp/project",
            "--tool", "/tmp/tool",
            "--state-dir", "/tmp/state",
            "--output-dir", "/tmp/output",
        ])

        #expect(arguments.input == .rootPath("/tmp/project"))
        #expect(arguments.toolPath == "/tmp/tool")
        #expect(arguments.stateDirectoryPath == "/tmp/state")
        #expect(arguments.outputDirectoryPath == "/tmp/output")
    }

    @Test("Manifest input is explicit and in-process")
    func parsesManifestInput() throws {
        let arguments = try parseValidationCoordinatorArguments([
            "--analysis-manifest", "/tmp/workspace-analysis.json",
            "--output-dir", "/tmp/output",
        ])

        #expect(
            arguments.input
                == .analysisManifestPath(
                    "/tmp/workspace-analysis.json"
                )
        )
        #expect(arguments.toolPath == nil)
        #expect(arguments.stateDirectoryPath == nil)
    }

    @Test("Workspace input contracts fail closed")
    func rejectsAmbiguousOrIncompleteInputs() {
        expectArgumentError(
            .conflictingWorkspaceInputs,
            arguments: [
                "--root", "/tmp/project",
                "--analysis-manifest", "/tmp/workspace-analysis.json",
                "--output-dir", "/tmp/output",
            ]
        )
        expectArgumentError(
            .externalToolUnsupportedForManifest,
            arguments: [
                "--analysis-manifest", "/tmp/workspace-analysis.json",
                "--tool", "/tmp/tool",
                "--output-dir", "/tmp/output",
            ]
        )
        expectArgumentError(
            .missingRequiredArguments,
            arguments: ["--output-dir", "/tmp/output"]
        )
        expectArgumentError(
            .missingRequiredArguments,
            arguments: ["--root", "/tmp/project"]
        )
        expectArgumentError(
            .duplicateOption("--root"),
            arguments: [
                "--root", "/tmp/one",
                "--root", "/tmp/two",
                "--output-dir", "/tmp/output",
            ]
        )
        expectArgumentError(
            .missingValue(option: "--analysis-manifest"),
            arguments: [
                "--analysis-manifest",
                "--output-dir", "/tmp/output",
            ]
        )
        expectArgumentError(
            .unknownOption("--workspace"),
            arguments: ["--workspace", "/tmp/project"]
        )
    }
}

private func expectArgumentError(
    _ expected: ValidationCoordinatorArgumentError,
    arguments: [String]
) {
    do {
        _ = try parseValidationCoordinatorArguments(arguments)
        Issue.record("Expected argument error: \(expected)")
    } catch let error as ValidationCoordinatorArgumentError {
        #expect(error == expected)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}
