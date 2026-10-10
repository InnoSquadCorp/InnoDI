import Foundation
import InnoDITestSupport
import Testing

@Suite("Build plugin command contracts", .serialized, .tags(.slow))
struct BuildPluginCommandContractTests {
    #if os(macOS)
    @Test("Native Xcode variants preserve validation without warnings or bundled reports")
    func xcodeCommandContract() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-B", "Tools/validate-xcode-plugin-contract.py"]
        process.currentDirectoryURL = packageRootURL()
        let result = try runCapturedProcess(process, timeoutSeconds: 900)
        #expect(!result.timedOut, Comment(rawValue: result.combinedOutput))
        #expect(result.exitCode == 0, Comment(rawValue: result.combinedOutput))
    }
    #endif

    @Test("SwiftPM preserves validation ordering without distributing reports")
    func swiftPMCommandContract() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-B", "Tools/validate-build-plugin-contract.py"]
        process.currentDirectoryURL = packageRootURL()
        let result = try runCapturedProcess(process, timeoutSeconds: 600)
        #expect(!result.timedOut, Comment(rawValue: result.combinedOutput))
        #expect(result.exitCode == 0, Comment(rawValue: result.combinedOutput))
    }
}
