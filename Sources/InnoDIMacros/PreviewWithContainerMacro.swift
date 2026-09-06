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
//  Expansion:
//
//      #Preview {
//          InnoDISwiftUI.DIContainerHost(
//              identity: false,
//              factory: { _ in AppContainer(baseURL: "https://example.com") },
//              content: { container, _ in ... },
//              loading: { SwiftUI.EmptyView() },
//              failure: { _, _ in SwiftUI.EmptyView() }
//          )
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
            context.emit(
                SimpleDiagnostic.previewWithContainerMissingContainerExpression(),
                at: Syntax(node)
            )
            return "()"
        }

        let previewClosure = node.trailingClosure
            ?? node.arguments.dropFirst().first?.expression.as(ClosureExprSyntax.self)

        guard let previewClosure else {
            context.emit(
                SimpleDiagnostic.previewWithContainerMissingTrailingClosure(),
                at: Syntax(node)
            )
            return "()"
        }

        guard let signature = previewClosure.signature,
              signature.declaresExactlyOneParameter else {
            context.emit(
                SimpleDiagnostic.previewWithContainerMissingContainerParameter(),
                at: Syntax(previewClosure)
            )
            return "()"
        }

        let bodyStatements = previewClosure.statements
        let signatureSource = signature.trimmedDescription + "\n"
        let bodySource = bodyStatements.map(\.trimmedDescription).joined(separator: "\n")
        let containerSource = containerExpression.trimmedDescription

        let expanded: ExprSyntax = """
        #Preview {
            InnoDISwiftUI.DIContainerHost(
                identity: false,
                factory: { _ in \(raw: containerSource) },
                content: { __innodi_preview_container, _ in
                    ({
                        \(raw: signatureSource)\(raw: bodySource)
                    })(__innodi_preview_container)
                },
                loading: { SwiftUI.EmptyView() },
                failure: { _, _ in SwiftUI.EmptyView() }
            )
        }
        """
        return expanded
    }
}

private extension ClosureSignatureSyntax {
    var declaresExactlyOneParameter: Bool {
        guard let parameterClause else {
            return false
        }

        switch parameterClause {
        case .simpleInput(let parameters):
            return parameters.count == 1
        case .parameterClause(let parameters):
            return parameters.parameters.count == 1
        }
    }
}
