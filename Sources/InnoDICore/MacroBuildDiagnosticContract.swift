/// Stable diagnostic identity and text shared by attached macros and
/// full-source build validators.
///
/// Source anchors, notes, remediation, and metadata remain consumer-owned;
/// only the semantic code and primary message belong here. This keeps the
/// compiler and build-plugin surfaces consistent without coupling their
/// different reporting models.
package enum MacroBuildDiagnosticContract {
    package static let containerCustomInitUnsupportedCode =
        "container.custom-init-unsupported"
    package static let subInvalidBindingsCode = "sub.invalid-bindings"
    package static let subUnknownChildInputCode = "sub.unknown-child-input"

    package static let containerCustomInitUnsupportedMessage =
        "@DIContainer does not support user-defined init declarations in the annotated type or any extension. Remove the custom init and use the synthesized initializer, or switch to manual wiring."

    package static func subInvalidBindingsMessage(
        memberName: String
    ) -> String {
        "@SubContainer on '\(memberName)' requires bindings: to be a literal array of (child:parent:) key-path tuples."
    }

    package static func subUnknownChildInputMessage(
        memberName: String,
        childInputName: String,
        childContainerName: String
    ) -> String {
        "@SubContainer on '\(memberName)' binds child input '\(childInputName)', but '\(childContainerName)' does not declare a matching @Input member."
    }
}
