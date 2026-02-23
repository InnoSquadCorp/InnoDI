import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

final class TestMacroExpansionContext: MacroExpansionContext {
    var diagnostics: [Diagnostic] = []
    var lexicalContext: [Syntax] { [] }

    func makeUniqueName(_ name: String) -> TokenSyntax {
        .identifier(name)
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
