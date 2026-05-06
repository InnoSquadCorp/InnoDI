//
//  PreviewWithContainerMacro.swift
//  InnoDIMacros
//
//  freestanding(expression) macro that wraps Xcode 16's `#Preview` so a
//  preview body can be expressed once with a typed container parameter
//  rather than the boilerplate of constructing the container, capturing
//  it in a `let`, and reading it back inside the trailing closure.
//
//  Surface:
//
//      #PreviewWithContainer(AppContainer(baseURL: "https://example.com")) { container in
//          container.dashboardRootView()
//      }
//
//      #PreviewWithContainer(AppContainer(baseURL: "https://example.com"), { container in
//          container.dashboardRootView()
//      })
//
//  Expansion (current MVP):
//
//      #Preview {
//          let __innodi_preview_container = AppContainer(baseURL: "https://example.com")
//          ({ container in
//              container.dashboardRootView()
//          })(__innodi_preview_container)
//      }
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct PreviewWithContainerMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        guard let containerExpression = node.arguments.first?.expression else {
            context.diagnose(
                Diagnostic(
                    node: Syntax(node),
                    message: SimpleDiagnostic.previewWithContainerMissingContainerExpression()
                )
            )
            return "()"
        }

        let previewClosure = node.trailingClosure
            ?? node.arguments.dropFirst().first?.expression.as(ClosureExprSyntax.self)

        guard let previewClosure else {
            context.diagnose(
                Diagnostic(
                    node: Syntax(node),
                    message: SimpleDiagnostic.previewWithContainerMissingTrailingClosure()
                )
            )
            return "()"
        }

        guard let signature = previewClosure.signature,
              signature.declaresAtLeastOneParameter else {
            context.diagnose(
                Diagnostic(
                    node: Syntax(previewClosure),
                    message: SimpleDiagnostic.previewWithContainerMissingContainerParameter()
                )
            )
            return "()"
        }

        let bodyStatements = previewClosure.statements
        let signatureSource = signature.trimmedDescription + "\n"
        let bodySource = bodyStatements.map(\.trimmedDescription).joined(separator: "\n")
        let containerSource = containerExpression.trimmedDescription

        let expanded: ExprSyntax = """
        #Preview {
            let __innodi_preview_container = \(raw: containerSource)
            ({
                \(raw: signatureSource)\(raw: bodySource)
            })(__innodi_preview_container)
        }
        """
        return expanded
    }
}

private extension ClosureSignatureSyntax {
    var declaresAtLeastOneParameter: Bool {
        guard let parameterClause else {
            return false
        }

        switch parameterClause {
        case .simpleInput(let parameters):
            return !parameters.isEmpty
        case .parameterClause(let parameters):
            return !parameters.parameters.isEmpty
        }
    }
}
