import SwiftUI

/// The state behind a `TabView`: the selected tab, plus one ``Navigator`` per tab.
///
/// Keep your own `TabView` (any tab style, the iOS 18 `Tab` API, `.tabItem`, a sidebar) and bind it to ``selection``:
///
/// ```swift
/// TabView(selection: tabs.selection) {
///     Tab("Feed", systemImage: "photo", value: AppTab.feed) { NavigationHost(tabs[.feed]) }
///     Tab("Profile", systemImage: "person", value: AppTab.profile) { NavigationHost(tabs[.profile]) }
/// }
/// ```
///
/// Tapping the tab that's already selected pops it back to its root, as UIKit tab bars do.
@MainActor
@Observable
public final class TabNavigator<Tab: Hashable> {
    public private(set) var selectedTab: Tab
    /// When `true`, tapping the selected tab pops it back to its root.
    public var popsToRootOnReselect: Bool
    @ObservationIgnored private var navigators: [Tab: Navigator]

    /// - Parameters:
    ///   - tabs: Each tab's navigator. These are created up front, which keeps every tab's state alive while you switch between them.
    public init(selectedTab: Tab, tabs: [Tab: Navigator], popsToRootOnReselect: Bool = true) {
        precondition(tabs[selectedTab] != nil, "Waypoint: the selected tab has no navigator.")
        self.selectedTab = selectedTab
        self.navigators = tabs
        self.popsToRootOnReselect = popsToRootOnReselect
    }

    public subscript(tab: Tab) -> Navigator {
        guard let navigator = navigators[tab] else {
            preconditionFailure("Waypoint: no navigator registered for tab \(tab).")
        }
        return navigator
    }

    /// The binding to give `TabView(selection:)`. The system writes the current tab again when it is tapped a second time.
    public var selection: Binding<Tab> {
        // Weak, so a TabView that SwiftUI keeps around after a root switch doesn't keep the tabs alive.
        let fallback = selectedTab
        return Binding(get: { [weak self] in self?.selectedTab ?? fallback }, set: { [weak self] in self?.userSelected($0) })
    }

    /// Switches tabs from code. Deep links use this before navigating inside the tab.
    public func select(_ tab: Tab, popToRoot: Bool = false) {
        selectedTab = tab
        if popToRoot {
            self[tab].dismissPresentation()
            self[tab].popToRoot()
        }
    }

    /// Tears down every tab. Call it when you discard the tabs, on sign out for example, so pending results resolve and coordinators finish right away.
    public func tearDown() {
        navigators.values.forEach { $0.tearDown() }
    }

    private func userSelected(_ tab: Tab) {
        if tab == selectedTab {
            if popsToRootOnReselect { self[tab].popToRoot() }
        } else {
            selectedTab = tab
        }
    }
}
