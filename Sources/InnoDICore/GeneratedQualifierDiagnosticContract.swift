/// Stable diagnostic text shared by attached macros and the target-scoped
/// full-source preflight.
///
/// Attached macros can inspect the annotated declaration, but Swift does not
/// provide sibling files or complete enclosing member lists to the expansion.
/// Keeping the user-facing contract here prevents the build validator from
/// drifting from the macro diagnostic for the same lookup failure.
package enum GeneratedQualifierDiagnosticContract {
    package static let containerReservedModuleNameCode =
        "container.reserved-module-name"

    package static let environmentBridgeReservedModuleNameCode =
        "swiftui.environment-bridge-reserved-module-name"

    package static let environmentBridgeExtensionContextUnsupportedCode =
        "swiftui.environment-bridge-extension-context-unsupported"

    /// Build-only boundary that cannot reliably reach an attached extension
    /// macro before Swift diagnoses the local declaration itself.
    package static let environmentBridgeLocalDeclarationUnsupportedCode =
        "swiftui.environment-bridge-local-declaration-unsupported"

    /// Build-only fail-closed boundary for superclass lookup that cannot be
    /// proven from the target-scoped source index.
    package static let inheritanceUnverifiableCode =
        "generated-qualifier.inheritance-unverifiable"

    package static func containerReservedModuleNameMessage(
        declarationName: String
    ) -> String {
        "Declaration '\(declarationName)' visible from the container shadows a module qualifier used by generated support. Rename the declaration so compiler-authored type and runtime references remain unambiguous."
    }

    package static func environmentBridgeReservedModuleNameMessage(
        declarationName: String
    ) -> String {
        "Declaration '\(declarationName)' visible from @DIEnvironmentBridge shadows a module qualifier used by generated SwiftUI support. Rename the declaration so the generated modifier remains unambiguous."
    }

    package static let environmentBridgeExtensionContextUnsupportedMessage =
        "@DIEnvironmentBridge cannot be attached to an extension or to a declaration nested in an extension in InnoDI 5.0. Move the bridge target into file or nominal scope so generated Swift and SwiftUI qualifiers can be validated."

    package static func environmentBridgeLocalDeclarationUnsupportedMessage(
        declarationName: String,
        context: String
    ) -> String {
        "@DIEnvironmentBridge cannot be attached to local declaration '\(declarationName)' in \(context) in InnoDI 5.0. Move the bridge target to file or nominal scope so its generated conformance has a stable lookup path."
    }

    package static func inheritanceUnverifiableMessage(
        className: String,
        inheritedType: String,
        resolutionState: String
    ) -> String {
        "Cannot verify inherited generated-qualifier lookup for class '\(className)' because its first inherited type '\(inheritedType)' is \(resolutionState) in the target-scoped source index. InnoDI 5.0 requires the superclass chain to be source-visible before generating dependency or environment-bridge support."
    }
}
