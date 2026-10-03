import Foundation
import Observation

/// A stand-in for a real auth service. It "signs in" after a short delay and remembers the user in memory.
@MainActor
@Observable
final class SessionStore {
    private(set) var user: User?

    init(user: User? = nil) {
        self.user = user
    }

    func signIn(email: String, password: String) async throws -> User {
        try await Task.sleep(for: .milliseconds(400))
        guard password.count >= 4 else { throw SignInError.wrongPassword }
        let user = User(name: email.split(separator: "@").first.map(String.init)?.capitalized ?? "Friend", email: email, favoriteColor: .indigo, interests: [])
        self.user = user
        return user
    }

    func register(_ user: User) {
        self.user = user
    }

    func update(_ user: User) {
        self.user = user
    }

    func signOut() {
        user = nil
    }
}

enum SignInError: LocalizedError {
    case wrongPassword

    var errorDescription: String? { "Passwords need at least 4 characters. Try \"1234\"." }
}
