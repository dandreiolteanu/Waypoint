import SwiftUI
import Waypoint

@MainActor
protocol LabNavigation: AnyObject {
    func showDetents(_ demo: DetentDemo)
    func showControlledDetent()
    func showEditor()
    func showCover()
    func showReplaceable()
    func showNestedSheets(depth: Int)
    func pushCard(_ index: Int)
    func presentCardSheet(_ index: Int)
    func presentCardCover(_ index: Int)
    func runWizard() async -> String?
    func showPopover(everywhere: Bool)
    func showToolbarPopover()
    func showSized(_ demo: SheetSizingDemo)
}

@MainActor
@Observable
final class LabViewModel {
    private(set) var wizardResult: String?
    private let navigation: LabNavigation

    init(navigation: LabNavigation) {
        self.navigation = navigation
        LifetimeTracker.track(self, kind: .viewModel)
    }

    func show(_ demo: DetentDemo) { navigation.showDetents(demo) }
    func showControlledDetent() { navigation.showControlledDetent() }
    func showEditor() { navigation.showEditor() }
    func showCover() { navigation.showCover() }
    func showReplaceable() { navigation.showReplaceable() }
    func showNestedSheets() { navigation.showNestedSheets(depth: 1) }
    func pushCard(_ index: Int) { navigation.pushCard(index) }
    func presentCardSheet(_ index: Int) { navigation.presentCardSheet(index) }
    func presentCardCover(_ index: Int) { navigation.presentCardCover(index) }
    func showPopover(everywhere: Bool) { navigation.showPopover(everywhere: everywhere) }
    func showToolbarPopover() { navigation.showToolbarPopover() }
    func showSized(_ demo: SheetSizingDemo) { navigation.showSized(demo) }

    func runWizard() async {
        wizardResult = await navigation.runWizard() ?? "Cancelled (popped before finishing)"
    }
}

struct LabView: View {
    let viewModel: LabViewModel

    var body: some View {
        List {
            Section("Sheets and detents") {
                ForEach(DetentDemo.allCases) { demo in
                    DemoRow(title: demo.title, subtitle: "presentationDetents", systemImage: "rectangle.bottomhalf.inset.filled") {
                        viewModel.show(demo)
                    }
                    .accessibilityIdentifier("lab.detent.\(demo.rawValue)")
                }
                DemoRow(title: "Detent driven by the coordinator", subtitle: "Presentation.selectedDetent is two-way", systemImage: "arrow.up.and.down.circle") {
                    viewModel.showControlledDetent()
                }
                .accessibilityIdentifier("lab.controlledDetent")
                DemoRow(title: "Unsaved changes", subtitle: "Swipe-to-dismiss locks while the form is dirty", systemImage: "lock.rectangle.stack") {
                    viewModel.showEditor()
                }
                .accessibilityIdentifier("lab.editor")
            }

            Section("Full screen and stacking") {
                DemoRow(title: "Full-screen cover", subtitle: ".fullScreenCover", systemImage: "rectangle.inset.filled") {
                    viewModel.showCover()
                }
                .accessibilityIdentifier("lab.cover")
                DemoRow(title: "Nested sheets", subtitle: "Child coordinators presenting child coordinators", systemImage: "square.stack.3d.up") {
                    viewModel.showNestedSheets()
                }
                .accessibilityIdentifier("lab.nested")
                DemoRow(title: "Replace a sheet with a cover", subtitle: "Waits for the sheet to finish dismissing", systemImage: "arrow.triangle.swap") {
                    viewModel.showReplaceable()
                }
                .accessibilityIdentifier("lab.replace")
            }

            Section {
                PopoverRow(
                    title: "Popover, sheet on iPhone",
                    subtitle: ".popover(from:) adapts in compact width",
                    source: PopoverSource.adaptive,
                    action: { viewModel.showPopover(everywhere: false) }
                )
                .accessibilityIdentifier("lab.popover")
                PopoverRow(
                    title: "Popover everywhere",
                    subtitle: "compactAdaptation: .popover",
                    source: PopoverSource.everywhere,
                    action: { viewModel.showPopover(everywhere: true) }
                )
                .accessibilityIdentifier("lab.popoverEverywhere")
                ForEach(SheetSizingDemo.allCases) { demo in
                    DemoRow(title: demo.title, subtitle: "sheet(sizing: .\(demo.rawValue)): visible on iPad", systemImage: "ipad") {
                        viewModel.showSized(demo)
                    }
                    .accessibilityIdentifier("lab.sizing.\(demo.rawValue)")
                }
            } header: {
                Text("iPad")
            }

            Section("Zoom") {
                CardRow(title: "Push", source: ExploreCoordinator.CardSource.push, onTap: viewModel.pushCard)
                CardRow(title: "Sheet", source: ExploreCoordinator.CardSource.sheet, onTap: viewModel.presentCardSheet)
                CardRow(title: "Cover", source: ExploreCoordinator.CardSource.cover, onTap: viewModel.presentCardCover)
            }

            Section {
                DemoRow(title: "Pushed child flow", subtitle: "Shares this stack, returns a value", systemImage: "wand.and.stars") {
                    Task { await viewModel.runWizard() }
                }
                .accessibilityIdentifier("lab.wizard")
                if let result = viewModel.wizardResult {
                    LabeledContent("Result", value: result)
                        .accessibilityIdentifier("lab.wizardResult")
                }
            } header: {
                Text("Results")
            }
        }
        .navigationTitle("Explore")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("About this lab", systemImage: "info.circle", action: viewModel.showToolbarPopover)
                    .popoverSource(id: PopoverSource.toolbar)
                    .accessibilityIdentifier("lab.toolbarPopover")
            }
        }
    }
}

/// A row whose trailing icon anchors a popover. The popover points at the icon on iPad.
private struct PopoverRow: View {
    let title: String
    let subtitle: String
    let source: PopoverSource
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "bubble.middle.top")
                    .font(.title3)
                    .frame(width: 32)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "info.circle")
                    .foregroundStyle(.tint)
                    .popoverSource(id: source)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private struct CardRow<Source: Hashable>: View {
    let title: String
    let source: (Int) -> Source
    let onTap: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Zoom \(title.lowercased())").font(.subheadline.weight(.medium))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(1...6, id: \.self) { index in
                        Button { onTap(index) } label: {
                            CardFace(index: index)
                                .frame(width: 76, height: 100)
                                .transitionSource(id: source(index))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("lab.card.\(title.lowercased()).\(index)")
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct CardFace: View {
    let index: Int

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(hue: Double(index) / 7, saturation: 0.6, brightness: 0.9).gradient)
            .overlay { Text("\(index)").font(.title.bold()).foregroundStyle(.white) }
    }
}

struct CardDetailView: View {
    let index: Int

    var body: some View {
        VStack(spacing: 24) {
            CardFace(index: index)
                .frame(maxWidth: 280, maxHeight: 380)
            Text("Card \(index)").font(.title.bold())
            Text("Swipe down or back to shrink it into its card.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Card \(index)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
