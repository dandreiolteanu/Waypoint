import SwiftUI
import Waypoint

/// A child coordinator pushed onto Profile's stack. It has its own routes and pushes onto the shared stack.
/// It's freed as soon as its first screen is popped. Watch the C count in the lifetime overlay.
@MainActor
final class SettingsCoordinator: FlowCoordinator {
    enum Route: Hashable {
        case list
        case notifications
        case about

        init?(pathComponent: String) {
            switch pathComponent {
            case "notifications": self = .notifications
            case "about": self = .about
            default: return nil
            }
        }
    }

    private let onSignOut: () -> Void

    init(onSignOut: @escaping () -> Void) {
        self.onSignOut = onSignOut
    }

    var initialRoute: Route { .list }

    func destination(for route: Route) -> some View {
        switch route {
        case .list:
            SettingsListView(
                onSelect: { self.push($0) },
                onSignOut: { Task { await self.confirmSignOut() } }
            )
        case .notifications:
            NotificationSettingsView()
        case .about:
            AboutView(onDone: { self.finish() })
        }
    }

    /// Alerts are coordinator decisions too. `confirm` shows one on the topmost navigator and awaits the answer.
    private func confirmSignOut() async {
        guard await confirm("Sign out?", message: "Every tab, coordinator and view model will be freed.", confirmTitle: "Sign out", role: .destructive) else { return }
        onSignOut()
    }
}

private struct SettingsListView: View {
    let onSelect: (SettingsCoordinator.Route) -> Void
    let onSignOut: () -> Void

    var body: some View {
        List {
            Section {
                DemoRow(title: "Notifications", subtitle: "Pushed by the settings coordinator", systemImage: "bell.badge") {
                    onSelect(.notifications)
                }
                .accessibilityIdentifier("settings.notifications")
                DemoRow(title: "About", subtitle: "Its Done button finishes the whole settings flow", systemImage: "info.circle") {
                    onSelect(.about)
                }
                .accessibilityIdentifier("settings.about")
            }
            Section {
                Button("Sign out", role: .destructive, action: onSignOut)
                    .accessibilityIdentifier("settings.signOut")
            } footer: {
                Text("Signing out swaps the app's root back to the auth flow. Every tab, coordinator and view model is freed.")
            }
        }
        .navigationTitle("Settings")
    }
}

private struct NotificationSettingsView: View {
    @State private var push = true
    @State private var email = false

    var body: some View {
        Form {
            Toggle("Push notifications", isOn: $push)
            Toggle("Email digest", isOn: $email)
        }
        .navigationTitle("Notifications")
    }
}

private struct AboutView: View {
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill").font(.system(size: 56)).foregroundStyle(.tint)
            Text("Waypoint Example").font(.title2.bold())
            Text("finish() pops back to whoever pushed this flow, however deep you are inside it.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("about.done")
        }
        .padding(24)
        .navigationTitle("About")
    }
}
