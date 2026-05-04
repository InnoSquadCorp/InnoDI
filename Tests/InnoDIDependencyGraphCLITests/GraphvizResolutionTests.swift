import Foundation
import Testing

@testable import InnoDI_DependencyGraph

@Suite("Graphviz executable resolution")
struct GraphvizResolutionTests {
    @Test("dot resolution searches PATH directly")
    func dotResolutionSearchesPathDirectly() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("innodi-dot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let dotURL = directory.appendingPathComponent("dot")
        try "#!/bin/sh\nexit 0\n".write(to: dotURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: dotURL.path(percentEncoded: false)
        )

        #expect(resolveDotExecutable(environment: ["PATH": directory.path(percentEncoded: false)]) == dotURL.path(percentEncoded: false))
    }
}
