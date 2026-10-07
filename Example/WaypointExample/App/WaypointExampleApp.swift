import SwiftUI
import Waypoint

@main
struct WaypointExampleApp: App {
    /// Shared by every window: one signed-in user per app.
    @State private var session = LaunchOptions.session()

    var body: some Scene {
        WindowGroup {
            SceneRoot(session: session)
        }
    }
}

/// One coordinator tree per window. On iPad, each window navigates independently, and a link opens in the window
/// the system routes it to.
struct SceneRoot: View {
    let session: SessionStore
    @State private var coordinator: AppCoordinator?

    var body: some View {
        if let coordinator {
            AppRootView(coordinator: coordinator)
                .onOpenURL { coordinator.open($0) }
        } else {
            Color.clear.onAppear { coordinator = AppCoordinator(session: session) }
        }
    }
}

struct AppRootView: View {
    let coordinator: AppCoordinator

    var body: some View {
        ZStack {
            switch coordinator.root {
            case .launching:
                ProgressView()
            case let .auth(navigator):
                NavigationHost(navigator)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            case let .main(main):
                MainView(tabs: main.tabs)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.45), value: coordinator.root.id)
        .overlay(alignment: .bottomTrailing) {
            if LaunchOptions.showsLifetimeOverlay {
                LifetimeOverlay()
            }
        }
    }
}

/// Switches the UI tests use to start in a known state.
enum LaunchOptions {
    static var arguments: [String] { ProcessInfo.processInfo.arguments }

    @MainActor
    static func session() -> SessionStore {
        guard arguments.contains("-signedIn") else { return SessionStore() }
        return SessionStore(user: User(name: "Ada", email: "ada@example.com", favoriteColor: .indigo, interests: [.travel]))
    }

    static var simulatesDoubleTap: Bool { arguments.contains("-simulateDoubleTap") }

    static var showsLifetimeOverlay: Bool {
        #if DEBUG
        !arguments.contains("-hideLifetimeOverlay")
        #else
        false
        #endif
    }
}
