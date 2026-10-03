import SwiftUI
import Waypoint

/// The top of the app: decides whether the signed-out flow or the tabs are on screen, and routes deep links.
///
/// Switching roots is plain state. The old root is torn down so its pending results resolve and its coordinators finish.
/// Dropping the reference then frees the whole tree (see the lifetime overlay).
@MainActor
@Observable
final class AppCoordinator {
    enum Root {
        case launching
        case auth(Navigator)
        case main(MainCoordinator)

        var id: String {
            switch self {
            case .launching: "launching"
            case .auth: "auth"
            case .main: "main"
            }
        }
    }

    private(set) var root: Root = .launching
    private let session: SessionStore
    /// A link that arrived while signed out. It's opened once the user signs in.
    @ObservationIgnored private var pendingDeepLink: DeepLink?

    init(session: SessionStore) {
        self.session = session
        if let user = session.user {
            showMain(user: user)
        } else {
            showAuth()
        }
    }

    func open(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }
        if case let .main(main) = root {
            main.open(link)
        } else {
            pendingDeepLink = link
        }
    }

    // MARK: - Roots

    private func showAuth() {
        let auth = AuthCoordinator(session: session, onSignedIn: { [weak self] user in
            self?.showMain(user: user)
        })
        replaceRoot(with: .auth(Navigator(root: auth)))
    }

    private func showMain(user: User) {
        let main = MainCoordinator(session: session, onSignOut: { [weak self] in
            self?.signOut()
        })
        replaceRoot(with: .main(main))
        if let link = pendingDeepLink {
            pendingDeepLink = nil
            main.open(link)
        }
    }

    private func signOut() {
        session.signOut()
        showAuth()
    }

    private func replaceRoot(with newRoot: Root) {
        switch root {
        case .launching: break
        case let .auth(navigator): navigator.tearDown()
        case let .main(main): main.tearDown()
        }
        root = newRoot
    }
}
