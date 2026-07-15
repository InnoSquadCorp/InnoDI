import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

final class TestMacroExpansionContext: MacroExpansionContext {
    var diagnostics: [Diagnostic] = []
    let lexicalContext: [Syntax]

    init(lexicalContext: [Syntax] = []) {
        self.lexicalContext = lexicalContext
    }

    func makeUniqueName(_ name: String) -> TokenSyntax {
        let unique = UUID().uuidString.replacingOccurrences(of: "-", with: "_")
        return .identifier("\(name)_\(unique)")
    }

    func diagnose(_ diagnostic: Diagnostic) {
        diagnostics.append(diagnostic)
    }

    func location(
        of node: some SyntaxProtocol,
        at position: PositionInSyntaxNode,
        filePathMode: SourceLocationFilePathMode
    ) -> AbstractSourceLocation? {
        nil
    }
}
