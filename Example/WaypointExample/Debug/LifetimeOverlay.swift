import SwiftUI
import Waypoint

/// A pill in the bottom-trailing corner, above the tab bar, with the number of live coordinators, navigators, screens and view models.
/// Walk into a flow and back out: every number should return to where it started. Tap it for the type names.
/// The UI tests read its accessibility value.
struct LifetimeOverlay: View {
    @State private var isExpanded = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let counts = LifetimeCounts.current
            VStack(alignment: .leading, spacing: 4) {
                Text(counts.summary)
                    .font(.caption2.monospaced().weight(.semibold))
                if isExpanded {
                    ForEach(Array(LifetimeTracker.liveTypeNames().enumerated()), id: \.offset) { _, name in
                        Text(name).font(.caption2.monospaced())
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 10))
            .onTapGesture { isExpanded.toggle() }
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("lifetime")
            .accessibilityLabel("Live objects: " + LifetimeTracker.liveTypeNames().joined(separator: ", "))
            .accessibilityValue(counts.accessibilityValue)
        }
        .padding(.trailing, 12)
        // Clears the tab bar.
        .padding(.bottom, 60)
    }
}

struct LifetimeCounts {
    let coordinators: Int
    let navigators: Int
    let entries: Int
    let viewModels: Int

    @MainActor
    static var current: LifetimeCounts {
        LifetimeCounts(
            coordinators: LifetimeTracker.liveCount(of: .coordinator),
            navigators: LifetimeTracker.liveCount(of: .navigator),
            entries: LifetimeTracker.liveCount(of: .entry),
            viewModels: LifetimeTracker.liveCount(of: .viewModel)
        )
    }

    var summary: String { "C \(coordinators) · N \(navigators) · S \(entries) · VM \(viewModels)" }
    var accessibilityValue: String { "c=\(coordinators) n=\(navigators) e=\(entries) vm=\(viewModels)" }
}
