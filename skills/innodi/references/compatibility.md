# Version and toolchain boundary

The [support record](support.json) supports stable InnoDI **7.0.x** (`>=7.0.0, <7.1.0`) and separately pins the validated baseline to public **7.0.0** at `4783eee7f674f99a337768c107b7a5f640810c2a`. The record's `version`, `revision`, toolchain and dependency fields describe that baseline. Its manifest requires SwiftSyntax **exact 604.0.0** and Swift tools 6.2; the consumer validation uses Xcode 27 / Swift 6.4. Deployment floors are iOS 17, macOS 14, watchOS 10, tvOS 17, and visionOS 1. Linux and older Apple toolchains are not validated by this skill.

Use the guidance for another stable 7.0.x patch without treating it as unsupported merely because the fixture is pinned to 7.0.0. Check that patch's release notes and resolved manifest for relevant behavior, dependency, toolchain, or platform changes; build/test the actual consumer. The baseline's exact SwiftSyntax constraint and toolchain result are not automatically evidence for every patch. Prereleases and versions outside 7.0.x need separate source/documentation review.

Check actual resolved dependencies before making compatibility claims. Existing application constraints take priority over the fixture's choice. Inspect local edits/overrides as well as `Package.resolved`, because a lock file alone does not prove the compiler used the remote release.

These particular release manifests have no SwiftSyntax intersection with InnoDI 7.0.0:

| Other release | SwiftSyntax constraint | Exact manifest |
|---|---|---|
| InnoFlow 5.1.1 | `603.0.0..<604.0.0` | [00a73ed](https://github.com/InnoSquadCorp/InnoFlow/blob/00a73ed2d2cb94114b0be5c9fbd59c187a4b67c7/Package.swift) |
| InnoRouter 6.1.0 | `603.0.2..<603.1.0` | [53fbb48](https://github.com/InnoSquadCorp/InnoRouter/blob/53fbb485a2b03b9e43c27d2e1c3e353f1b58682a/Package.swift) |
| InnoNetwork 6.0.0 | `603.0.1..<603.1.0` | [9d8053d](https://github.com/InnoSquadCorp/InnoNetwork/blob/9d8053d5f921ebf5c38cc2f816efe90c7db4a450/Package.swift) |

This is a comparison of fixed manifests, not a claim about every newer release or a combined consumer build. Installing multiple AI skills does not require their Swift packages to share a graph; linking them into one application does. A newer Xcode cannot resolve disjoint package-version constraints.

On a conflict, show the actual requirements and look for a compatible published combination. Explain any required dependency change and keep it within the user's requested migration. Do not silently downgrade InnoDI, substitute `main`, use local path overrides, or edit upstream constraints. Validate the selected combination separately before claiming it works.
