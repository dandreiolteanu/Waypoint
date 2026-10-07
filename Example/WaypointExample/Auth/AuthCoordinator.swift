import SwiftUI
import Waypoint

/// The signed-out flow. It ends by calling `onSignedIn`, and the app coordinator then swaps the root to the tabs.
@MainActor
final class AuthCoordinator: FlowCoordinator {
    enum Route: Hashable {
        case welcome
        case signIn
        case forgotPassword(email: String)
    }

    private let session: SessionStore
    private let onSignedIn: (User) -> Void

    init(session: SessionStore, onSignedIn: @escaping (User) -> Void) {
        self.session = session
        self.onSignedIn = onSignedIn
    }

    var initialRoute: Route { .welcome }

    func destination(for route: Route) -> some View {
        switch route {
        case .welcome:
            WelcomeView(
                onSignIn: { self.push(.signIn) },
                onCreateAccount: { Task { await self.createAccount() } },
                onQuickSignIn: { try await self.quickSignIn() }
            )
        case .signIn:
            SignInView(viewModel: SignInViewModel(session: session, navigation: self))
        case let .forgotPassword(email):
            ForgotPasswordView(email: email, onDone: { self.dismissPresented() })
        }
    }

    /// Signs in with the demo account, skipping the form.
    private func quickSignIn() async throws {
        onSignedIn(try await session.signIn(email: "ada@example.com", password: "1234"))
    }

    /// Onboarding is a child flow with several screens and a shared draft. It hands back the finished `User`, or `nil` if cancelled.
    private func createAccount() async {
        guard let user = await presentFlow(as: .fullScreenCover, { OnboardingCoordinator(onComplete: $0) }) else { return }
        session.register(user)
        onSignedIn(user)
    }
}

extension AuthCoordinator: SignInNavigation {
    func showForgotPassword(email: String) {
        present(.forgotPassword(email: email), as: .sheet(detents: [.medium], dragIndicator: .visible))
    }

    func didSignIn(_ user: User) {
        onSignedIn(user)
    }
}
