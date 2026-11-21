import SwiftSyntax

// Member-level availability for generated mocks.
//
// A mock keeps every requirement's stubs and call history in stored
// properties, and Swift does not let a stored property be potentially
// unavailable. A requirement whose own `@available` restricts a platform
// beyond what the consumer's deployment target guarantees therefore cannot be
// mocked by a peer class: its types may not exist at the deployment target.
// The macro cannot see that target. It knows one lower bound, InnoDI's own
// minimum platforms (a consumer cannot deploy below a dependency's minimum),
// and the availability written on the protocol and its enclosing
// declarations, which a peer mock inherits.

/// InnoDI's minimum deployment targets, kept equal to `Package.swift`'s
/// `platforms` (a test checks that they stay in sync). Mac Catalyst follows
/// the iOS minimum.
let innoDIMinimumPlatformVersions: [String: [Int]] = [
    "iOS": [17],
    "macOS": [14],
    "macCatalyst": [17],
    "tvOS": [17],
    "watchOS": [10],
    "visionOS": [1],
]

/// The reason a requirement's own `@available` prevents synthesis, or `nil`
/// when every platform restriction it writes is already guaranteed by InnoDI's
/// minimum platforms or by `enclosingAttributes` (the protocol's and its
/// enclosing declarations' attributes). Deprecation, renaming, messages, and
/// `noasync` do not restrict where the requirement exists and stay accepted.
func unsupportedMockMemberAvailability(
    _ attributes: AttributeListSyntax,
    enclosingAttributes: [AttributeListSyntax]
) -> String? {
    let guaranteed = enclosingAttributes.reduce(into: innoDIMinimumPlatformVersions) { result, list in
        for (platform, version) in introducedPlatformVersions(in: list) {
            // Keep the later of InnoDI's floor and the enclosing declaration's.
            if let existing = result[platform], isVersion(existing, atLeast: version) {
                continue
            }
            result[platform] = version
        }
    }
    for restriction in platformRestrictions(in: attributes) {
        switch restriction {
        case .introduced(let platform, let version):
            if let floor = guaranteed[platform], isVersion(floor, atLeast: version) {
                continue
            }
            return "platform @available cannot guard the mock's stored stubs; put it on the protocol"
        case .removed:
            return "platform @available cannot guard the mock's stored stubs; put it on the protocol"
        }
    }
    return nil
}

private enum MockPlatformRestriction {
    /// Available from `version` on `platform`.
    case introduced(platform: String, version: [Int])
    /// Obsoleted or unavailable somewhere; never implied by the enclosing scope.
    case removed
}

private func platformRestrictions(in attributes: AttributeListSyntax) -> [MockPlatformRestriction] {
    availabilityArgumentLists(in: attributes).flatMap { arguments -> [MockPlatformRestriction] in
        let entries = Array(arguments)
        guard let first = entries.first else { return [] }
        // Long form: `@available(<platform | *>, introduced:/obsoleted:/unavailable ...)`.
        if case .token(let token) = first.argument, entries.count > 1 {
            // A language-version restriction never changes which types exist.
            guard !languageVersionPlatforms.contains(token.text) else { return [] }
            let platform = canonicalPlatformName(token.text)
            var restrictions: [MockPlatformRestriction] = []
            for entry in entries.dropFirst() {
                switch entry.argument {
                case .token(let flag) where flag.text == "unavailable":
                    restrictions.append(.removed)
                case .availabilityLabeledArgument(let labeled):
                    switch labeled.label.text {
                    case "introduced":
                        if case .version(let version) = labeled.value, let platform {
                            restrictions.append(.introduced(platform: platform, version: versionComponents(version)))
                        } else {
                            restrictions.append(.removed)
                        }
                    case "obsoleted":
                        restrictions.append(.removed)
                    default:
                        continue
                    }
                default:
                    continue
                }
            }
            return restrictions
        }
        // Shorthand: `@available(macOS 14, iOS 17, *)`.
        return entries.compactMap { entry in
            guard case .availabilityVersionRestriction(let restriction) = entry.argument,
                  !languageVersionPlatforms.contains(restriction.platform.text) else {
                return nil
            }
            guard let platform = canonicalPlatformName(restriction.platform.text),
                  let version = restriction.version else {
                return .removed
            }
            return .introduced(platform: platform, version: versionComponents(version))
        }
    }
}

private let languageVersionPlatforms: Set<String> = ["swift", "_PackageDescription"]

private func introducedPlatformVersions(in attributes: AttributeListSyntax) -> [(String, [Int])] {
    platformRestrictions(in: attributes).compactMap {
        guard case .introduced(let platform, let version) = $0 else { return nil }
        return (platform, version)
    }
}

private func availabilityArgumentLists(in attributes: AttributeListSyntax) -> [AvailabilityArgumentListSyntax] {
    attributes.compactMap { element in
        guard let attribute = element.as(AttributeSyntax.self),
              attribute.attributeName.trimmedDescription == "available",
              case .availability(let arguments)? = attribute.arguments else {
            return nil
        }
        return arguments
    }
}

/// The platform key for `name`, or `nil` for a name the macro cannot place
/// relative to InnoDI's minimums (`swift`, `*`, or an unknown platform).
private func canonicalPlatformName(_ name: String) -> String? {
    let base = name.hasSuffix("ApplicationExtension")
        ? String(name.dropLast("ApplicationExtension".count))
        : name
    switch base {
    case "OSX": return "macOS"
    case "xrOS": return "visionOS"
    default:
        return innoDIMinimumPlatformVersions[base] == nil ? nil : base
    }
}

private func versionComponents(_ version: VersionTupleSyntax) -> [Int] {
    version.trimmedDescription.split(separator: ".").map { Int($0) ?? Int.max }
}

/// Whether `lhs` is the same version as `rhs` or later.
private func isVersion(_ lhs: [Int], atLeast rhs: [Int]) -> Bool {
    for index in 0..<max(lhs.count, rhs.count) {
        let left = index < lhs.count ? lhs[index] : 0
        let right = index < rhs.count ? rhs[index] : 0
        if left != right { return left > right }
    }
    return true
}
