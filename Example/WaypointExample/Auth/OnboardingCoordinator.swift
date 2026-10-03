import SwiftUI
import Waypoint

/// The answers collected across the onboarding screens.
/// The flow's coordinator owns it and hands the same instance to every step. That's how data moves forward through a multi-screen flow.
@MainActor
@Observable
final class OnboardingDraft {
    var name = ""
    var color: ProfileColor = .indigo
    var interests: Set<Interest> = []

    init() {
        LifetimeTracker.track(self, kind: .viewModel)
    }
}

/// A presented, multi-step child flow that returns a `User` through its callback. Cancelling returns `nil` to the awaiting parent.
@MainActor
final class OnboardingCoordinator: FlowCoordinator {
    enum Route: Hashable {
        case name, color, interests, summary
    }

    private let draft = OnboardingDraft()
    private let onComplete: Callback<User>

    init(onComplete: Callback<User>) {
        self.onComplete = onComplete
    }

    var initialRoute: Route { .name }

    func destination(for route: Route) -> some View {
        Group {
            switch route {
            case .name:
                OnboardingNameStep(draft: draft, onNext: { self.push(.color) })
            case .color:
                OnboardingColorStep(draft: draft, onNext: { self.push(.interests) })
            case .interests:
                OnboardingInterestsStep(draft: draft, onNext: { self.push(.summary) })
            case .summary:
                OnboardingSummaryStep(draft: draft, onFinish: { self.complete() })
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { self.finish() }
                    .accessibilityIdentifier("onboarding.cancel")
            }
        }
    }

    private func complete() {
        let name = draft.name.trimmingCharacters(in: .whitespaces)
        onComplete(User(name: name, email: "\(name.lowercased())@example.com", favoriteColor: draft.color, interests: draft.interests))
    }
}

// MARK: - Steps

private struct OnboardingNameStep: View {
    @Bindable var draft: OnboardingDraft
    let onNext: () -> Void

    var body: some View {
        Form {
            Section("What should we call you?") {
                TextField("Name", text: $draft.name)
                    .accessibilityIdentifier("onboarding.name")
            }
        }
        .navigationTitle("Step 1 of 3")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Next", action: onNext)
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("onboarding.next")
            }
        }
    }
}

private struct OnboardingColorStep: View {
    @Bindable var draft: OnboardingDraft
    let onNext: () -> Void

    var body: some View {
        List(ProfileColor.allCases) { color in
            Button {
                draft.color = color
            } label: {
                HStack {
                    Circle().fill(color.color).frame(width: 24, height: 24)
                    Text(color.title)
                    Spacer()
                    if draft.color == color { Image(systemName: "checkmark").foregroundStyle(.tint) }
                }
            }
            .tint(.primary)
        }
        .navigationTitle("Hi \(draft.name), pick a color")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Next", action: onNext).accessibilityIdentifier("onboarding.next")
            }
        }
    }
}

private struct OnboardingInterestsStep: View {
    @Bindable var draft: OnboardingDraft
    let onNext: () -> Void

    var body: some View {
        List(Interest.allCases) { interest in
            Toggle(interest.title, isOn: Binding(
                get: { draft.interests.contains(interest) },
                set: { isOn in
                    if isOn { draft.interests.insert(interest) } else { draft.interests.remove(interest) }
                }
            ))
        }
        .navigationTitle("Step 3 of 3")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Next", action: onNext).accessibilityIdentifier("onboarding.next")
            }
        }
    }
}

private struct OnboardingSummaryStep: View {
    let draft: OnboardingDraft
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Circle()
                .fill(draft.color.color.gradient)
                .frame(width: 96, height: 96)
                .overlay { Text(draft.name.prefix(1)).font(.largeTitle.bold()).foregroundStyle(.white) }
            Text("Welcome, \(draft.name)").font(.title.bold())
            Text(draft.interests.isEmpty ? "No interests picked" : draft.interests.map(\.title).sorted().formatted())
                .foregroundStyle(.secondary)
            Text("Every step edited the same draft. Finishing hands a User back to the awaiting coordinator.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Create account", action: onFinish)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("onboarding.finish")
        }
        .padding(24)
        .navigationTitle("All set")
    }
}
