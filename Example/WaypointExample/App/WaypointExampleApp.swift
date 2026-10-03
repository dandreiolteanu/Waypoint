import SwiftUI
import Waypoint

@main
struct WaypointExampleApp: App {
    @State private var coordinator = AppCoordinator(session: LaunchOptions.session())

    var body: some Scene {
        WindowGroup {
            AppRootView(coordinator: coordinator)
                .onOpenURL { coordinator.open($0) }
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
        .overlay(alignment: .topLeading) {
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

    static var showsLifetimeOverlay: Bool {
        #if DEBUG
        !arguments.contains("-hideLifetimeOverlay")
        #else
        false
        #endif
    }
}
