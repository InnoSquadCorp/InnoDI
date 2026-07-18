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

        #expect(
            manifest.contains(
                #".package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "603.0.2")"#
            )
        )
        #expect(!manifest.contains("603.0.1"))
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
        #expect(source.contains(#"swift-syntax\.git\", exact: \"603\.0\.2\""#))
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
        #expect(
            resolved.originHash
                == "8abd2d2bd3b65148be10d6988a158f723070727f13ece23ac698ca62876ad0a7"
        )
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
        #expect(swiftSyntax.state.revision == "79e4b74a295b6eb74a8b585e3a39d29e70c1dbd1")
        #expect(swiftSyntax.state.version == "603.0.2")
    }
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
