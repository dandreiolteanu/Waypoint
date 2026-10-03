import SwiftUI
import Waypoint

struct DetentDemoView: View {
    let demo: DetentDemo
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.bottomhalf.inset.filled").font(.largeTitle).foregroundStyle(.tint)
            Text(demo.title).font(.headline)
            Text("Drag the indicator to move between detents.").font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(demo.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { CloseButton(action: onClose) }
        .accessibilityIdentifier("detentDemo")
    }
}

/// The coordinator writes `Presentation.selectedDetent`, and the sheet moves. Dragging the sheet writes it back the other way.
struct ControlledDetentView: View {
    static let detents: Set<PresentationDetent> = [.fraction(0.25), .medium, .large]

    let onSelect: (PresentationDetent) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Ask the coordinator to move the sheet").font(.headline)
            HStack {
                Button("Small") { onSelect(.fraction(0.25)) }.accessibilityIdentifier("detent.small")
                Button("Medium") { onSelect(.medium) }.accessibilityIdentifier("detent.medium")
                Button("Large") { onSelect(.large) }.accessibilityIdentifier("detent.large")
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity)
        .navigationTitle("Driven detent")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { CloseButton(action: onClose) }
    }
}

// MARK: - Editor

@MainActor
protocol EditorNavigation: AnyObject {
    func setDismissLocked(_ isLocked: Bool)
    func closeEditor()
}

@MainActor
@Observable
final class EditorViewModel {
    var text = "" {
        didSet { navigation.setDismissLocked(isDirty) }
    }
    var isConfirmingDiscard = false
    private let navigation: EditorNavigation

    init(navigation: EditorNavigation) {
        self.navigation = navigation
        LifetimeTracker.track(self, kind: .viewModel)
    }

    var isDirty: Bool { !text.isEmpty }

    func cancel() {
        if isDirty { isConfirmingDiscard = true } else { navigation.closeEditor() }
    }

    func discard() { navigation.closeEditor() }
    func save() { navigation.closeEditor() }
}

struct EditorView: View {
    @Bindable var viewModel: EditorViewModel

    var body: some View {
        Form {
            Section {
                TextField("Write something…", text: $viewModel.text, axis: .vertical)
                    .lineLimit(4...8)
                    .accessibilityIdentifier("editor.text")
            } footer: {
                Text(viewModel.isDirty ? "Swipe-to-dismiss is locked until you save or discard." : "Type something, then try swiping the sheet down.")
            }
        }
        .navigationTitle("Unsaved changes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: viewModel.cancel).accessibilityIdentifier("editor.cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: viewModel.save).disabled(!viewModel.isDirty)
            }
        }
        .confirmationDialog("Discard your changes?", isPresented: $viewModel.isConfirmingDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive, action: viewModel.discard)
                .accessibilityIdentifier("editor.discard")
        }
    }
}

// MARK: - Covers

struct CoverView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.inset.filled").font(.system(size: 56)).foregroundStyle(.tint)
            Text("Full-screen cover").font(.title.bold())
            Text("Covers can't be swiped away, so the close button dismisses it through the coordinator.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.accentColor.opacity(0.08))
        .navigationTitle("Cover")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { CloseButton(action: onClose) }
        .accessibilityIdentifier("cover")
    }
}

struct ReplaceableSheetView: View {
    let onReplace: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("SwiftUI drops a presentation started while another one is still animating out. Waypoint queues it until the sheet has gone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Replace with a full-screen cover", action: onReplace)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("replace.action")
        }
        .padding(24)
        .navigationTitle("Replaceable")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { CloseButton(action: onClose) }
    }
}

// MARK: - Nested sheets

/// A presented coordinator that can present another copy of itself. Each level has its own stack and can push too.
@MainActor
final class NestedSheetCoordinator: FlowCoordinator {
    enum Route: Hashable {
        case level
        case pushed
    }

    let depth: Int

    init(depth: Int) {
        self.depth = depth
    }

    var initialRoute: Route { .level }

    func destination(for route: Route) -> some View {
        switch route {
        case .level:
            NestedSheetView(
                depth: depth,
                onPresentNext: { self.presentNext(remaining: 1) },
                onPush: { self.push(.pushed) },
                onDismiss: { self.dismiss() },
                onDismissAll: { self.navigator?.dismissAll() }
            )
        case .pushed:
            Text("Pushed inside sheet level \(depth)")
                .navigationTitle("Pushed")
                .accessibilityIdentifier("nested.pushedScreen")
        }
    }

    func presentNext(remaining: Int) {
        guard remaining > 0 else { return }
        let next = NestedSheetCoordinator(depth: depth + 1)
        present(child: next, as: .sheet(detents: depth.isMultiple(of: 2) ? [.large] : [.medium, .large]))
        next.presentNext(remaining: remaining - 1)
    }
}

private struct NestedSheetView: View {
    let depth: Int
    let onPresentNext: () -> Void
    let onPush: () -> Void
    let onDismiss: () -> Void
    let onDismissAll: () -> Void

    var body: some View {
        List {
            Section {
                Text("Level \(depth)").font(.title2.bold()).accessibilityIdentifier("nested.level.\(depth)")
            }
            Section {
                Button("Present level \(depth + 1)", action: onPresentNext).accessibilityIdentifier("nested.presentNext.\(depth)")
                Button("Push a screen in this sheet", action: onPush).accessibilityIdentifier("nested.push.\(depth)")
                Button("Dismiss this level", action: onDismiss).accessibilityIdentifier("nested.dismiss.\(depth)")
                Button("Dismiss all", role: .destructive, action: onDismissAll).accessibilityIdentifier("nested.dismissAll.\(depth)")
            }
        }
        .navigationTitle("Sheet \(depth)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Wizard

/// A child flow pushed onto Explore's own stack. Finishing pops all of its screens and returns the answer to the awaiting parent.
@MainActor
final class WizardCoordinator: FlowCoordinator {
    enum Route: Hashable {
        case step(Int)
    }

    private let onFinish: Callback<String>
    /// Keyed by step, so going back and answering again replaces the old answer.
    private var answers: [Int: String] = [:]

    init(onFinish: Callback<String>) {
        self.onFinish = onFinish
    }

    var initialRoute: Route { .step(1) }

    func destination(for route: Route) -> some View {
        switch route {
        case let .step(number):
            WizardStepView(number: number, isLast: number == 3) { answer in
                self.answers[number] = answer
                if number == 3 {
                    self.onFinish((1...3).compactMap { self.answers[$0] }.joined(separator: " → "))
                } else {
                    self.push(.step(number + 1))
                }
            }
        }
    }
}

private struct WizardStepView: View {
    let number: Int
    let isLast: Bool
    let onAnswer: (String) -> Void

    var body: some View {
        List {
            Section("Step \(number) of 3: pick one") {
                ForEach(["Alpha", "Bravo", "Charlie"], id: \.self) { option in
                    Button(option) { onAnswer(option) }
                        .accessibilityIdentifier("wizard.option.\(option)")
                }
            }
            Section {
                Text(isLast ? "Picking finishes the flow. It pops all three steps and returns your answers." : "Swipe back at any step and the parent gets nil.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Wizard")
    }
}
