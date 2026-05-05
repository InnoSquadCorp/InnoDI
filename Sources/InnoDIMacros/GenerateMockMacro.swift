//
//  GenerateMockMacro.swift
//  InnoDIMacros
//
//  RFC 0001 (`@GenerateMock`) experimental skeleton.
//
//  Surface — attach `@GenerateMock` to a protocol declaration to have
//  the macro synthesize a `Mock` peer with call-recording storage,
//  per-method stubs, and protocol conformance:
//
//      @GenerateMock
//      protocol UserService {
//          func fetch(id: String) async throws -> User
//      }
//
//  Subsequent RFC 0001 commits flesh out the protocol-extraction stage
//  (peer mock declaration with method mirror) and the Overrides-builder
//  bundling option. This file ships the experimental gate, attribute
//  validation, and the diagnostic surface so consumers can adopt the
//  attribute incrementally without paying for a half-finished
//  expansion.
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

public struct GenerateMockMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let protocolDecl = declaration.as(ProtocolDeclSyntax.self) else {
            context.diagnose(
                Diagnostic(
                    node: Syntax(node),
                    message: SimpleDiagnostic.generateMockRequiresProtocol()
                )
            )
            return []
        }

        // The skeleton drop validates the attribute placement and emits a
        // single informational diagnostic so downstream tests can confirm
        // the macro plugin sees the attribute. Subsequent RFC commits
        // replace the empty peer declarations with the real mock body.
        context.diagnose(
            Diagnostic(
                node: Syntax(node),
                message: SimpleDiagnostic.generateMockExperimentalSkeleton(
                    protocolName: protocolDecl.name.text
                )
            )
        )
        return []
    }
}
