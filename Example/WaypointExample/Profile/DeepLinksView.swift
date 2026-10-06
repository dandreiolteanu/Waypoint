import SwiftUI

/// Every link the app handles, opened through the system with `openURL`, exactly as if it came from Safari, another app,
/// or a widget. The system hands it to this window's `onOpenURL`, and from there it goes down the coordinator tree.
struct DeepLinksView: View {
    @Environment(\.openURL) private var openURL

    private let links: [(title: String, url: String)] = [
        ("Photo in Feed", "waypoint://feed/photo/3"),
        ("Album (split view)", "waypoint://albums/sky"),
        ("Photo inside an album", "waypoint://albums/sky/photo/7"),
        ("Three stacked sheets", "waypoint://explore/nested/3"),
        ("Unsaved-changes editor", "waypoint://explore/editor"),
        ("Settings", "waypoint://profile/settings"),
        ("About, inside Settings", "waypoint://profile/settings/about"),
        ("Pick a color (awaits a result)", "waypoint://profile/color"),
    ]

    var body: some View {
        List {
            Section {
                ForEach(links, id: \.url) { link in
                    Button {
                        openURL(URL(string: link.url)!)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(link.title)
                            Text(link.url).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("link.\(link.url)")
                }
            } footer: {
                Text("Every link resets its tab first, so it lands the same way wherever you are. Open the editor, type something, then open another link: the app asks before discarding your draft.")
            }

            Section {
                Button("Simulate a notification tap") {
                    // What `userNotificationCenter(_:didReceive:)` would do with the payload.
                    let payload: [AnyHashable: Any] = ["link": "waypoint://feed/photo/5"]
                    if let url = NotificationRouting.url(from: payload) { openURL(url) }
                }
                .accessibilityIdentifier("link.notification")
            } footer: {
                Text("Notifications carry a link in their payload and take the same path as any URL.")
            }
        }
        .navigationTitle("Deep links")
    }
}
