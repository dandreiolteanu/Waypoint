import SwiftUI
import Waypoint

struct WelcomeView: View {
    let onSignIn: () -> Void
    let onCreateAccount: () -> Void
    let onQuickSignIn: () async throws -> Void
    @State private var isSigningIn = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
            VStack(spacing: 8) {
                Text("Waypoint").font(.largeTitle.bold())
                Text("Coordinators for SwiftUI navigation. Every flow in this app is driven by one.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(spacing: 12) {
                Button(action: onSignIn) {
                    Text("Sign in").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("welcome.signIn")
                Button(action: onCreateAccount) {
                    Text("Create account").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("welcome.createAccount")
                Button {
                    isSigningIn = true
                    Task {
                        try? await onQuickSignIn()
                        isSigningIn = false
                    }
                } label: {
                    HStack {
                        Text("Sign in as Ada")
                        if isSigningIn { ProgressView() }
                    }
                }
                .disabled(isSigningIn)
                .accessibilityIdentifier("welcome.quickSignIn")
            }
            .controlSize(.large)
        }
        .padding(24)
    }
}

/// What the sign-in screen needs from its coordinator. Depending on a protocol keeps the view model testable without Waypoint.
@MainActor
protocol SignInNavigation: AnyObject {
    func showForgotPassword(email: String)
    func didSignIn(_ user: User)
}

@MainActor
@Observable
final class SignInViewModel {
    var email = "ada@example.com"
    var password = ""
    private(set) var isSigningIn = false
    private(set) var errorMessage: String?

    private let session: SessionStore
    private let navigation: SignInNavigation

    init(session: SessionStore, navigation: SignInNavigation) {
        self.session = session
        self.navigation = navigation
        LifetimeTracker.track(self, kind: .viewModel)
    }

    var canSubmit: Bool { !email.isEmpty && !password.isEmpty && !isSigningIn }

    func signIn() async {
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }
        do {
            navigation.didSignIn(try await session.signIn(email: email, password: password))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func forgotPassword() {
        navigation.showForgotPassword(email: email)
    }
}

struct SignInView: View {
    @Bindable var viewModel: SignInViewModel

    var body: some View {
        Form {
            Section {
                TextField("Email", text: $viewModel.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                SecureField("Password (try 1234)", text: $viewModel.password)
                    .accessibilityIdentifier("signIn.password")
            } footer: {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            Section {
                Button {
                    Task { await viewModel.signIn() }
                } label: {
                    HStack {
                        Text("Sign in")
                        if viewModel.isSigningIn { Spacer(); ProgressView() }
                    }
                }
                .disabled(!viewModel.canSubmit)
                .accessibilityIdentifier("signIn.submit")
                Button("Forgot password?", action: viewModel.forgotPassword)
                    .accessibilityIdentifier("signIn.forgot")
            }
        }
        .navigationTitle("Sign in")
    }
}

struct ForgotPasswordView: View {
    let email: String
    let onDone: () -> Void
    @State private var isSent = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: isSent ? "checkmark.circle.fill" : "envelope.badge")
                .font(.system(size: 44))
                .foregroundStyle(isSent ? .green : .accentColor)
                .contentTransition(.symbolEffect(.replace))
            Text(isSent ? "Check your inbox" : "Reset your password").font(.title2.bold())
            Text(isSent ? "We sent a link to \(email)." : "We'll email a reset link to \(email).")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(isSent ? "Done" : "Send link") {
                if isSent { onDone() } else { withAnimation { isSent = true } }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("forgot.action")
        }
        .padding(24)
        .navigationTitle("Medium detent")
        .navigationBarTitleDisplayMode(.inline)
    }
}
