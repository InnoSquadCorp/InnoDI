import Foundation
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

    @Test("Xcode configuration and SDK variants have distinct outputs")
    func resolvesXcodeVariants() throws {
        let input = ["--analysis-manifest", "/tmp/analysis.json", "--xcode-output-base", "/tmp/plugin output"]
        let variants: [(String, String, String)] = [
            ("Debug", "-iphoneos", "iphoneos"),
            ("Debug", "-watchos", "watchos"),
            ("Debug", "-iphonesimulator", "iphonesimulator"),
            ("Release", "-iphoneos", "iphoneos"),
            ("Debug", "", "macosx"),
            ("Debug", "-maccatalyst", "macosx"),
        ]
        var paths: Set<String> = []
        for (configuration, effectivePlatform, platform) in variants {
            let arguments = try parseValidationCoordinatorArguments(input, environment: [
                "CONFIGURATION": configuration,
                "EFFECTIVE_PLATFORM_NAME": effectivePlatform,
                "PLATFORM_NAME": platform,
            ])
            #expect(arguments.outputDirectoryPath == "/tmp/plugin output/xcode/\(configuration)\(effectivePlatform)/\(platform)/")
            paths.insert(arguments.outputDirectoryPath)
        }
        #expect(paths.count == variants.count)
    }

    @Test("Xcode output routing rejects missing and escaping build settings")
    func rejectsUnsafeXcodeVariants() {
        let input = ["--analysis-manifest", "/tmp/analysis.json", "--xcode-output-base", "/tmp/output"]
        #expect(throws: ValidationCoordinatorArgumentError.invalidXcodeBuildSetting("CONFIGURATION")) {
            try parseValidationCoordinatorArguments(input, environment: [:])
        }
        for value in ["..", "/tmp/escape", "one/two", "bad\0component"] {
            #expect(throws: ValidationCoordinatorArgumentError.invalidXcodeBuildSetting("PLATFORM_NAME")) {
                try parseValidationCoordinatorArguments(input, environment: ["CONFIGURATION": "Debug", "PLATFORM_NAME": value])
            }
        }
        #expect(throws: ValidationCoordinatorArgumentError.conflictingOutputDirectories) {
            try parseValidationCoordinatorArguments(input + ["--output-dir", "/tmp/other"], environment: [:])
        }
    }

    @Test("Native output language is explicit even when a workspace contains peer Swift sources")
    func nativeOutputLanguage() throws {
        let input = ["--analysis-manifest", "/tmp/analysis.json", "--xcode-output-base", "/tmp/output"]
        let environment = ["CONFIGURATION": "Debug", "PLATFORM_NAME": "macosx"]
        for kind in [XcodeValidationSourceKind.swift, .clang] {
            let arguments = try parseValidationCoordinatorArguments(input + ["--xcode-source-kind", kind.rawValue], environment: environment)
            #expect(arguments.xcodeSourceKind == kind)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let result = ValidationCommandResult(exitCode: 0, stdout: "", stderr: "")
            try writeXcodeValidationOrderingInput(kind: kind, signature: "checked", result: result, to: directory)
            let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            #expect(files == [kind == .swift ? "_InnoDIDAGValidation.generated.swift" : "_InnoDIDAGValidation.generated.h"])
            let file = directory.appendingPathComponent(try #require(files.first))
            let firstDate = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            try writeXcodeValidationOrderingInput(kind: kind, signature: "checked", result: result, to: directory)
            #expect(try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == firstDate)
        }
        #expect(throws: ValidationCoordinatorArgumentError.invalidXcodeSourceKind("objc")) {
            try parseValidationCoordinatorArguments(input + ["--xcode-source-kind", "objc"], environment: environment)
        }
        #expect(throws: ValidationCoordinatorArgumentError.xcodeOutputRequiresManifest) {
            try parseValidationCoordinatorArguments(["--root", "/tmp/root", "--xcode-output-base", "/tmp/output"], environment: environment)
        }
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
