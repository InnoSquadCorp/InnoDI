@testable import InnoDIMigrationCore
import Testing

/// Planning parses each migrated file again, so a rewrite defect that emits
/// invalid Swift blocks the run instead of reaching disk.
@Suite("Migration output validation")
struct MigrationOutputValidationTests {
    @Test("Output that does not parse is detected before any write")
    func unparseableOutputIsDetected() {
        #expect(migratedSourceHasSyntaxErrors("import SwiftUIimport Foundation\nstruct A {"))
        #expect(!migratedSourceHasSyntaxErrors("import SwiftUI; import Foundation\nstruct A {}\n"))
    }
}
