import InnoDIDependencyGraphCore
import Testing

@testable import InnoDIDependencyGraphCLI

@Suite("CLI argument parsing")
struct ArgumentsParsingTests {
    @Test("Render invocation captures target input and pruning scope")
    func recognizedRenderOptions() {
        guard case let .parsed(args, warnings) = parseArguments([
            "--analysis-manifest", "/tmp/workspace.json",
            "--root-pruning", "roots",
            "--format", "json",
            "--output", "out.json",
        ]) else {
            Issue.record("Expected parsed result")
            return
        }
        #expect(args.input == .analysisManifest("/tmp/workspace.json"))
        #expect(args.rootPruning == .roots)
        #expect(args.format == .json)
        #expect(args.output == "out.json")
        #expect(args.validateDAG == false)
        #expect(warnings.isEmpty)
    }

    @Test("Validation captures one full-scope input")
    func recognizedValidationOptions() {
        guard case let .parsed(args, warnings) = parseArguments([
            "--root", "/tmp/project",
            "--validate-dag",
            "--output", "validation.txt",
        ]) else {
            Issue.record("Expected parsed result")
            return
        }
        #expect(args.input == .root("/tmp/project"))
        #expect(args.rootPath == "/tmp/project")
        #expect(args.rootPruning == nil)
        #expect(args.output == "validation.txt")
        #expect(args.validateDAG)
        #expect(warnings.isEmpty)
    }

    @Test(
        "Format option accepts supported renderers",
        arguments: [
            ("mermaid", OutputFormat.mermaid),
            ("dot", OutputFormat.dot),
            ("ascii", OutputFormat.ascii),
            ("json", OutputFormat.json),
        ]
    )
    func supportedFormats(rawValue: String, expected: OutputFormat) {
        let input = rawValue == "json"
            ? ["--analysis-manifest", "/tmp/manifest.json"]
            : ["--root", "/tmp/project"]
        guard case let .parsed(args, warnings) = parseArguments(
            input + [
                "--root-pruning", "all",
                "--format", rawValue,
            ]
        ) else {
            Issue.record("Expected parsed result")
            return
        }
        #expect(args.format == expected)
        #expect(warnings.isEmpty)
    }

    @Test("--output - is accepted as stdout")
    func outputDashIsAccepted() {
        guard case let .parsed(args, warnings) = parseArguments([
            "--root", "/tmp/project",
            "--root-pruning", "all",
            "--output", "-",
        ]) else {
            Issue.record("Expected parsed result")
            return
        }
        #expect(args.output == "-")
        #expect(warnings.isEmpty)
    }

    @Test("Maintenance commands retain an optional root")
    func maintenanceRoot() {
        guard case let .parsed(args, warnings) = parseArguments([
            "--root", "/tmp/project",
            "--cache-stats",
        ]) else {
            Issue.record("Expected parsed result")
            return
        }
        #expect(args.rootPath == "/tmp/project")
        #expect(args.cacheStatsPath == "")
        #expect(warnings.isEmpty)
    }

    @Test("Help short-circuits parsing")
    func helpShortCircuits() {
        #expect(parseArguments(["--help"]) == .helpRequested)
        #expect(parseArguments(["-h"]) == .helpRequested)
    }

    @Test("Missing option value surfaces as a failure")
    func missingOptionValue() {
        #expect(
            parseArguments(["--root"])
                == .failed(.missingOptionValue(option: "--root"))
        )
    }

    @Test("Option followed by another flag is a missing value")
    func optionFollowedByFlag() {
        #expect(
            parseArguments(["--root", "--validate-dag"])
                == .failed(.missingOptionValue(option: "--root"))
        )
    }

    @Test("Unknown options and positional arguments fail")
    func unknownInputsFail() {
        #expect(
            parseArguments(["--ignored", "value"])
                == .failed(.unknownOption(option: "--ignored"))
        )
        #expect(
            parseArguments(["project"])
                == .failed(.unexpectedArgument(value: "project"))
        )
    }

    @Test("Formats and pruning modes reject unknown values")
    func invalidEnumValues() {
        #expect(
            parseArguments([
                "--root", "/tmp/project",
                "--root-pruning", "all",
                "--format", "yaml",
            ]) == .failed(.invalidFormat(value: "yaml"))
        )
        #expect(
            parseArguments([
                "--root", "/tmp/project",
                "--root-pruning", "automatic",
            ]) == .failed(.invalidRootPruning(value: "automatic"))
        )
    }

    @Test("Graph commands require exactly one input")
    func exactlyOneInput() {
        #expect(parseArguments([]) == .failed(.missingGraphInput))
        #expect(
            parseArguments([
                "--root", "/tmp/project",
                "--analysis-manifest", "/tmp/manifest.json",
                "--root-pruning", "all",
            ]) == .failed(
                .mutuallyExclusiveOptions(
                    first: "--root",
                    second: "--analysis-manifest"
                )
            )
        )
    }

    @Test("Render commands require explicit root pruning")
    func explicitRootPruning() {
        #expect(
            parseArguments(["--root", "/tmp/project"])
                == .failed(.missingRootPruning)
        )
    }

    @Test("Validation rejects render-only options")
    func validationRejectsRenderOptions() {
        #expect(
            parseArguments([
                "--root", "/tmp/project",
                "--validate-dag",
                "--root-pruning", "all",
            ]) == .failed(.rootPruningWithValidation)
        )
        #expect(
            parseArguments([
                "--root", "/tmp/project",
                "--validate-dag",
                "--format", "ascii",
            ]) == .failed(.formatWithValidation)
        )
    }

    @Test("JSON schema v2 rejects legacy root scans")
    func jsonRequiresManifest() {
        #expect(
            parseArguments([
                "--root", "/tmp/project",
                "--root-pruning", "all",
                "--format", "json",
            ]) == .failed(.jsonRequiresAnalysisManifest)
        )
    }

    @Test("Every option may be specified only once")
    func duplicateOptionsFail() {
        #expect(
            parseArguments([
                "--root", "/tmp/one",
                "--root", "/tmp/two",
                "--root-pruning", "all",
            ]) == .failed(.duplicateOption(option: "--root"))
        )
    }

    @Test("Maintenance commands reject graph-only options")
    func maintenanceRejectsGraphOptions() {
        #expect(
            parseArguments([
                "--cache-stats",
                "--root-pruning", "all",
            ]) == .failed(
                .incompatibleMaintenanceOption(option: "--root-pruning")
            )
        )
        #expect(
            parseArguments([
                "--cache-stats",
                "--diagnose-lock",
            ]) == .failed(
                .mutuallyExclusiveOptions(
                    first: "--diagnose-lock",
                    second: "--cache-stats"
                )
            )
        )
    }
}
