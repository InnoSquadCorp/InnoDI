import Foundation
import InnoDITestSupport
import Testing

@Suite("Build plugin command contracts", .serialized, .tags(.slow))
struct BuildPluginCommandContractTests {
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
