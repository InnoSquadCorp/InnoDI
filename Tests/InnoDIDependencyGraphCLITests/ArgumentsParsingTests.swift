import Testing

@testable import InnoDIDependencyGraphCLI

@Suite("CLI argument parsing")
struct ArgumentsParsingTests {
    @Test("Default invocation returns parsed values with nil format")
    func defaultInvocation() {
        guard case let .parsed(args, warnings) = parseArguments([]) else {
            Issue.record("Expected parsed result")
            return
        }
        #expect(args.format == nil)
        #expect(args.output == nil)
        #expect(args.validateDAG == false)
        #expect(warnings.isEmpty)
    }

    @Test("Recognized options populate the struct")
    func recognizedOptions() {
        guard case let .parsed(args, warnings) = parseArguments([
            "--root", "/tmp/project",
            "--format", "dot",
            "--output", "out.txt",
            "--validate-dag"
        ]) else {
            Issue.record("Expected parsed result")
            return
        }
        #expect(args.root == "/tmp/project")
        #expect(args.format == .dot)
        #expect(args.output == "out.txt")
        #expect(args.validateDAG == true)
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
        guard case let .parsed(args, warnings) = parseArguments(["--format", rawValue]) else {
            Issue.record("Expected parsed result")
            return
        }
        #expect(args.format == expected)
        #expect(warnings.isEmpty)
    }

    @Test("--output - is accepted as stdout")
    func outputDashIsAccepted() {
        guard case let .parsed(args, warnings) = parseArguments(["--output", "-"]) else {
            Issue.record("Expected parsed result")
            return
        }
        #expect(args.output == "-")
        #expect(warnings.isEmpty)
    }

    @Test("Unknown options are returned as warnings")
    func unknownOptionsAreWarnings() {
        guard case let .parsed(args, warnings) = parseArguments(["--ignored", "value"]) else {
            Issue.record("Expected parsed result")
            return
        }
        #expect(args.format == nil)
        #expect(warnings == ["Warning: unrecognized option '--ignored'"])
    }

    @Test("--help short-circuits parsing")
    func helpShortCircuits() {
        #expect(parseArguments(["--help"]) == .helpRequested)
        #expect(parseArguments(["-h"]) == .helpRequested)
    }

    @Test("Missing option value surfaces as a failure")
    func missingOptionValue() {
        let result = parseArguments(["--root"])
        #expect(result == .failed(.missingOptionValue(option: "--root")))
    }

    @Test("Option followed by another flag is treated as missing value")
    func optionFollowedByFlag() {
        let result = parseArguments(["--root", "--validate-dag"])
        #expect(result == .failed(.missingOptionValue(option: "--root")))
    }

    @Test("Invalid format value is rejected")
    func invalidFormat() {
        let result = parseArguments(["--format", "yaml"])
        #expect(result == .failed(.invalidFormat(value: "yaml")))
    }
}
