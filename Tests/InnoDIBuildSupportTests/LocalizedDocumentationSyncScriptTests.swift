import Foundation
import Testing

@Suite("Localized documentation sync script contracts")
struct LocalizedDocumentationSyncScriptTests {
    @Test("Korean README and DocC articles with matching structure pass")
    func matchingKoreanDocumentationPasses() throws {
        let fixture = try LocalizedDocumentationFixture()
        defer { fixture.remove() }

        let result = try fixture.runSyncCheck()

        #expect(result.exitCode == 0)
        #expect(result.output.contains("OK README.ko.md:"))
        #expect(
            result.output.contains(
                "OK Sources/InnoDI/InnoDI.docc/ko.lproj/Guide.md: swift_fences=1 h2_headers=2"
            )
        )
        #expect(result.output.contains("1 localized DocC article(s) match"))
    }

    @Test("An English DocC article without a Korean mirror fails in strict mode")
    func englishArticleWithoutKoreanMirrorFails() throws {
        let fixture = try LocalizedDocumentationFixture()
        defer { fixture.remove() }
        try fixture.write("\(LocalizedDocumentationFixture.catalog)/EnglishOnly.md", """
            # English Only

            ## Overview

            ```swift
            let english = true
            ```
            """)

        let result = try fixture.runSyncCheck()

        #expect(result.exitCode == 1)
        #expect(
            result.output.contains(
                "::error file=Sources/InnoDI/InnoDI.docc/ko.lproj/EnglishOnly.md::missing localized counterpart of Sources/InnoDI/InnoDI.docc/EnglishOnly.md"
            )
        )
    }

    @Test("A Korean DocC article that drops a Swift fence or H2 fails in strict mode")
    func koreanArticleDriftFails() throws {
        let fixture = try LocalizedDocumentationFixture()
        defer { fixture.remove() }
        try fixture.write("\(LocalizedDocumentationFixture.catalog)/ko.lproj/Guide.md", """
            # 가이드

            ## 개요

            예제가 없습니다.
            """)

        let result = try fixture.runSyncCheck()

        #expect(result.exitCode == 1)
        #expect(
            result.output.contains(
                "::error file=Sources/InnoDI/InnoDI.docc/ko.lproj/Guide.md::structure drift against Sources/InnoDI/InnoDI.docc/Guide.md (swift_fences=0 want=1, h2_headers=1 want=2)"
            )
        )
        #expect(result.output.contains("::error::1 localized documentation contract drift(s)"))
    }

    @Test("INNODI_README_SYNC_STRICT=0 demotes Korean DocC drift to a warning")
    func nonStrictModeWarns() throws {
        let fixture = try LocalizedDocumentationFixture()
        defer { fixture.remove() }
        try fixture.write("\(LocalizedDocumentationFixture.catalog)/ko.lproj/Guide.md", "# 가이드\n")

        let result = try fixture.runSyncCheck(strict: "0")

        #expect(result.exitCode == 0)
        #expect(
            result.output.contains(
                "::warning file=Sources/InnoDI/InnoDI.docc/ko.lproj/Guide.md::structure drift"
            )
        )
        #expect(result.output.contains("(strict mode disabled)"))
    }

    @Test("Frozen translations and Korean pages without an English counterpart are not compared")
    func uncomparedPagesDoNotFail() throws {
        let fixture = try LocalizedDocumentationFixture()
        defer { fixture.remove() }
        try fixture.write("\(LocalizedDocumentationFixture.catalog)/ja.lproj/Guide.md", "# ガイド\n")
        try fixture.write("\(LocalizedDocumentationFixture.catalog)/ko.lproj/KoreanOnly.md", "# 한국어 전용\n")

        let result = try fixture.runSyncCheck()

        #expect(result.exitCode == 0)
        #expect(!result.output.contains("ja.lproj"))
        #expect(
            result.output.contains(
                "SKIP Sources/InnoDI/InnoDI.docc/ko.lproj/KoreanOnly.md: no English counterpart"
            )
        )
        #expect(result.output.contains("1 localized DocC article(s) match"))
    }

    @Test("An empty or missing Korean DocC catalog fails instead of passing vacuously")
    func emptyKoreanCatalogFails() throws {
        let fixture = try LocalizedDocumentationFixture()
        defer { fixture.remove() }
        let koreanCatalog = fixture.rootURL.appendingPathComponent(
            "\(LocalizedDocumentationFixture.catalog)/ko.lproj",
            isDirectory: true
        )

        try FileManager.default.removeItem(at: koreanCatalog.appendingPathComponent("Guide.md"))
        let empty = try fixture.runSyncCheck()

        #expect(empty.exitCode == 1)
        #expect(
            empty.output.contains(
                "::error file=Sources/InnoDI/InnoDI.docc/ko.lproj::no localized DocC article with an English counterpart was compared"
            )
        )

        try FileManager.default.removeItem(at: koreanCatalog)
        let missing = try fixture.runSyncCheck()

        #expect(missing.exitCode == 1)
        #expect(
            missing.output.contains(
                "::error file=Sources/InnoDI/InnoDI.docc/ko.lproj::missing localized DocC catalog"
            )
        )
        #expect(missing.output.contains("::error::1 localized documentation contract drift(s)"))
    }
}

/// A repository copy holding the localized README contract and a small DocC
/// catalog. The README pair reuses the canonical README so the fixture keeps
/// every critical parity token the script requires.
private struct LocalizedDocumentationFixture {
    static let catalog = "Sources/InnoDI/InnoDI.docc"

    let rootURL: URL
    private let scriptURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "InnoDI-LocalizedDocumentationSync-\(UUID().uuidString)",
            isDirectory: true
        )
        scriptURL = rootURL.appendingPathComponent("Tools/check-localized-readme-sync.sh")
        try FileManager.default.createDirectory(
            at: scriptURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(
            at: packageRootURL().appendingPathComponent("Tools/check-localized-readme-sync.sh"),
            to: scriptURL
        )

        let readme = try String(
            contentsOf: packageRootURL().appendingPathComponent("README.md"),
            encoding: .utf8
        )
        try write("README.md", readme)
        try write("README.ko.md", readme)
        for name in ["README.ja.md", "README.zh-Hans.md", "README.de.md", "README.es.md", "README.ru.md"] {
            try write(name, """
                [README.md](README.md)

                https://github.com/InnoSquadCorp/InnoDI/blob/6.0.0/\(name)
                """)
        }

        try write("\(Self.catalog)/Guide.md", """
            # Guide

            ## Overview

            An example follows.

            ```swift
            let value = 1
            ```

            ## Details

            More text.
            """)
        try write("\(Self.catalog)/ko.lproj/Guide.md", """
            # 가이드

            ## 개요

            예제는 다음과 같습니다.

            ```swift
            let value = 1
            ```

            ## 자세히

            추가 설명입니다.
            """)
        try write(
            "\(Self.catalog)/ja.lproj/TranslationNotice-ja.md",
            "# InnoDI (ja)\n\nThis DocC translation is frozen at InnoDI 6.0.0.\n"
        )
    }

    func write(_ relativePath: String, _ contents: String) throws {
        let url = rootURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try (contents + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    func runSyncCheck(strict: String? = nil) throws -> LocalizedDocumentationSyncResult {
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "InnoDI-LocalizedDocumentationSyncOutput-\(UUID().uuidString).log"
        )
        _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        process.standardOutput = outputHandle
        process.standardError = outputHandle

        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "INNODI_README_SYNC_STRICT")
        if let strict {
            environment["INNODI_README_SYNC_STRICT"] = strict
        }
        process.environment = environment

        try process.run()
        process.waitUntilExit()
        try outputHandle.synchronize()
        try outputHandle.close()

        return LocalizedDocumentationSyncResult(
            exitCode: process.terminationStatus,
            output: try String(contentsOf: outputURL, encoding: .utf8)
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private struct LocalizedDocumentationSyncResult {
    let exitCode: Int32
    let output: String
}
