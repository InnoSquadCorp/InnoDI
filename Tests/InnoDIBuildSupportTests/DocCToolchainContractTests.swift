import Foundation
import Testing

@Suite("DocC toolchain contracts")
struct DocCToolchainContractTests {
    @Test("DocC generation uses the checked-in exact dependency graph")
    func generatorUsesCheckedInExactDependencyGraph() throws {
        let root = packageRootURL()
        let source = try String(
            contentsOf: root.appendingPathComponent("Tools/generate-docc.sh"),
            encoding: .utf8
        )
        let manifest = try String(
            contentsOf: root.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let syntaxVersion = try exactSwiftSyntaxVersion(manifest)
        #expect(source.contains(#"DOCC_PLUGIN_VERSION="1.5.0""#))
        #expect(
            source.contains(
                #"DOCS_RESOLVED_PATH="$ROOT_DIR/Tools/docc/Package.resolved""#
            )
        )
        #expect(source.contains(#"[[ ! -s "$DOCS_RESOLVED_PATH" ]]"#))
        #expect(
            source.contains(
                #"cp "$DOCS_RESOLVED_PATH" "$DOCS_PACKAGE_DIR/Package.resolved""#
            )
        )
        #expect(
            source.contains(
                #"python3 - "$DOCS_MANIFEST_PATH" "$DOCC_PLUGIN_VERSION""#
            )
        )
        #expect(source.contains(#"exact: "{docc_plugin_version}""#))
        let escapedVersion = syntaxVersion.replacingOccurrences(of: ".", with: #"\."#)
        #expect(source.contains(#"swift-syntax\.git\", exact: \""# + escapedVersion + #"\""#))
        #expect(source.contains("--disable-automatic-resolution"))
        #expect(source.contains(#"--allow-writing-to-directory "$OUTPUT_DIR""#))
        #expect(!source.contains(#"from: "1.4.0""#))
        #expect(!source.contains("swift package resolve"))
    }

    @Test("DocC dependency lock pins every resolved revision and version")
    func dependencyLockPinsExactRevisions() throws {
        let data = try Data(
            contentsOf: packageRootURL()
                .appendingPathComponent("Tools/docc/Package.resolved")
        )
        let resolved = try JSONDecoder().decode(DocCResolvedFile.self, from: data)
        let pins = Dictionary(
            uniqueKeysWithValues: resolved.pins.map { ($0.identity, $0) }
        )

        #expect(resolved.version == 3)
        #expect(resolved.originHash.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil)
        #expect(
            Set(pins.keys) == [
                "swift-docc-plugin",
                "swift-docc-symbolkit",
                "swift-syntax",
            ]
        )

        let plugin = try #require(pins["swift-docc-plugin"])
        #expect(plugin.kind == "remoteSourceControl")
        #expect(plugin.location == "https://github.com/swiftlang/swift-docc-plugin")
        #expect(plugin.state.revision == "647c708be89f834fa6a6d4945442793a77ddf5b6")
        #expect(plugin.state.version == "1.5.0")

        let symbolKit = try #require(pins["swift-docc-symbolkit"])
        #expect(symbolKit.kind == "remoteSourceControl")
        #expect(symbolKit.location == "https://github.com/swiftlang/swift-docc-symbolkit")
        #expect(symbolKit.state.revision == "b45d1f2ed151d057b54504d653e0da5552844e34")
        #expect(symbolKit.state.version == "1.0.0")

        let swiftSyntax = try #require(pins["swift-syntax"])
        #expect(swiftSyntax.kind == "remoteSourceControl")
        #expect(swiftSyntax.location == "https://github.com/swiftlang/swift-syntax.git")
        let root = packageRootURL()
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        let syntaxVersion = try exactSwiftSyntaxVersion(manifest)
        // Compare against the graph SwiftPM actually resolved for the build,
        // rather than repeating a soon-stale version/revision literal.
        let rootResolved = try JSONDecoder().decode(
            DocCResolvedFile.self,
            from: Data(contentsOf: root.appendingPathComponent("Package.resolved"))
        )
        let rootSyntax = try #require(rootResolved.pins.first { $0.identity == "swift-syntax" })
        #expect(swiftSyntax.state.version == syntaxVersion)
        #expect(rootSyntax.state.version == syntaxVersion)
        #expect(swiftSyntax.state.revision == rootSyntax.state.revision)
        #expect(swiftSyntax.state.revision.range(of: #"^[0-9a-f]{40}$"#, options: .regularExpression) != nil)
    }
}

private func exactSwiftSyntaxVersion(_ manifest: String) throws -> String {
    let regex = try NSRegularExpression(
        pattern: #"swift-syntax\.git", exact: "([0-9]+\.[0-9]+\.[0-9]+)""#
    )
    let matches = regex.matches(in: manifest, range: NSRange(manifest.startIndex..., in: manifest))
    #expect(matches.count == 1)
    let match = try #require(matches.first)
    let range = try #require(Range(match.range(at: 1), in: manifest))
    return String(manifest[range])
}

private struct DocCResolvedFile: Decodable {
    let originHash: String
    let pins: [Pin]
    let version: Int

    struct Pin: Decodable {
        let identity: String
        let kind: String
        let location: String
        let state: State

        struct State: Decodable {
            let revision: String
            let version: String
        }
    }
}
