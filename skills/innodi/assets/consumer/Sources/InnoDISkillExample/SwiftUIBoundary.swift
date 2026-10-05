import SwiftUI
import InnoDISwiftUI

// The view receives the already composed dependency. It owns no global resolver.
@MainActor
struct ClientSummary: View {
    let client: APIClient
    var body: some View { Text(client.baseURL) }
}

@MainActor
func makePreview() -> some View {
    let services = AppServices(baseURL: "https://example.invalid", count: ConstructionCount()) {
        $0.client = APIClient(baseURL: "preview")
    }
    return ClientSummary(client: services.client)
}
