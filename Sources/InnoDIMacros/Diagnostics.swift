//
//  Diagnostics.swift
//  InnoDIMacros
//

import SwiftDiagnostics

struct SimpleDiagnostic: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity

    init(_ message: String, severity: DiagnosticSeverity = .error) {
        self.message = message
        self.diagnosticID = MessageID(domain: "InnoDI", id: message)
        self.severity = severity
    }
}
