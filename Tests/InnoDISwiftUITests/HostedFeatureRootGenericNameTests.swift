import InnoDISwiftUI
import SwiftUI
import Testing

// The hosted feature-root helper is generic over the host identity. A child
// container named `Identity` shares that helper's signature, so this file
// compiles only while the generated generic parameter cannot shadow it.
@DIContainerRole(role: ContainerRole.local, mainActor: true)
fileprivate struct Identity {
    @Input var label: String
}

@MainActor
private struct IdentityRootView: View {
    let container: Identity

    var body: some View {
        Text(container.label)
    }
}

@DIContainerRole(role: ContainerRole.local, mainActor: true)
fileprivate struct IdentityHostParent {
    @Input var label: String

    @SubContainer(
        scope: .transient,
        with: [\Self.label],
        featureRoots: [FeatureRoot(IdentityRootView.self, hosted: true)]
    )
    var identity: Identity
}

@Suite("Hosted feature-root generic names")
struct HostedFeatureRootGenericNameTests {
    @MainActor
    @Test("A child type named Identity is not shadowed by the hosted helper")
    func childTypeNamedIdentityCompiles() {
        let parent = IdentityHostParent(label: "root")
        let close: DIContainerHostOwner<Int, Identity>.Close = { _ in }
        _ = parent.identityRootView(identity: 1, close: close)
        #expect(parent.identity.label == "root")
    }
}
