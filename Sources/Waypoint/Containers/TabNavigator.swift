import SwiftUI

/// The state behind a `TabView`: which tab is selected, plus one ``Navigator`` (one stack) per tab.
///
/// ```swift
/// enum AppTab: CaseIterable { case feed, profile }
///
/// let tabs = TabNavigator(selected: AppTab.feed) { tab in
///     switch tab {
///     case .feed: Navigator(root: FeedCoordinator())
///     case .profile: Navigator(root: ProfileCoordinator())
///     }
/// }
/// ```
///
/// Show it with ``TabHost`` and your own `TabView` (any style, the iOS 18 `Tab` API or `.tabItem`), bound to ``selection``.
/// Every tab keeps its stack while you switch away. Tapping the selected tab again pops it to its root, as UIKit does.
@MainActor
@Observable
public final class TabNavigator<Tab: Hashable> {
    /// The selected tab.
    public private(set) var selectedTab: Tab
    /// Whether tapping the selected tab again pops it to its root. On by default.
    public var popsToRootOnReselect: Bool
    @ObservationIgnored private var navigators: [Tab: Navigator]
    /// Observed by ``TabHost``, which renders nothing once the tabs are torn down.
    private(set) var isTornDown = false

    /// Creates a navigator for each tab in `tabs`.
    ///
    /// - Parameters:
    ///   - selected: The tab shown first.
    ///   - tabs: Every tab, in any order.
    ///   - popsToRootOnReselect: Whether tapping the selected tab again pops it to its root.
    ///   - navigator: Builds each tab's navigator. It's called once per tab, right away.
    public init(selected: Tab, tabs: [Tab], popsToRootOnReselect: Bool = true, navigator: (Tab) -> Navigator) {
        precondition(tabs.contains(selected), "Waypoint: the selected tab \(selected) isn't in `tabs`.")
        self.selectedTab = selected
        self.navigators = Dictionary(tabs.map { ($0, navigator($0)) }, uniquingKeysWith: { first, _ in first })
        self.popsToRootOnReselect = popsToRootOnReselect
    }

    /// The navigator of `tab`. After ``tearDown()`` it's an empty placeholder, so a tab view SwiftUI still holds renders nothing.
    public subscript(tab: Tab) -> Navigator {
        if let navigator = navigators[tab] { return navigator }
        precondition(isTornDown, "Waypoint: no navigator for tab \(tab). Include it in `tabs`.")
        return Navigator.placeholder
    }

    /// The coordinator at the root of `tab`, as `C`. Reach a tab's flow for a deep link without keeping your own reference:
    /// `tabs.coordinator(for: .feed, as: FeedCoordinator.self)?.showPhoto(id)`.
    public func coordinator<C: Coordinator>(for tab: Tab, as type: C.Type) -> C? {
        navigators[tab]?.rootCoordinator(as: type)
    }

    /// The binding for `TabView(selection:)`. The system writes the current tab again when it's tapped a second time,
    /// which is how reselection pops to root.
    public var selection: Binding<Tab> {
        // Weak, so a TabView that SwiftUI keeps around after a root switch doesn't keep the tabs alive.
        let fallback = selectedTab
        return Binding(get: { [weak self] in self?.selectedTab ?? fallback }, set: { [weak self] in self?.userSelected($0) })
    }

    /// Selects `tab` from code. Pass `reset: true` for a deep link: it dismisses every tab's sheets and alerts (they cover
    /// the whole window, whichever tab opened them) and pops `tab` to its root.
    public func select(_ tab: Tab, reset: Bool = false) {
        selectedTab = tab
        guard reset else { return }
        navigators.values.forEach {
            $0.dismissAlerts()
            $0.dismissPresentation()
        }
        self[tab].popToRoot()
    }

    /// Ends every tab: pending awaits return `nil`, every coordinator's ``Coordinator/didFinish()`` runs, and the tabs'
    /// navigators are released. Call it when you discard the tabs, on sign-out for example. Even if a view (or SwiftUI)
    /// still holds this object afterwards, it holds nothing else.
    public func tearDown() {
        guard !isTornDown else { return }
        isTornDown = true
        navigators.values.forEach { $0.tearDown() }
        navigators.removeAll()
    }

    private func userSelected(_ tab: Tab) {
        if tab == selectedTab {
            if popsToRootOnReselect { self[tab].popToRoot() }
        } else {
            selectedTab = tab
        }
    }
}

extension TabNavigator where Tab: CaseIterable {
    /// Creates a navigator for every case of `Tab`. Switching over `tab` in `navigator` is checked for exhaustiveness.
    ///
    /// - Parameters:
    ///   - selected: The tab shown first.
    ///   - popsToRootOnReselect: Whether tapping the selected tab again pops it to its root.
    ///   - navigator: Builds each tab's navigator. It's called once per tab, right away.
    public convenience init(selected: Tab, popsToRootOnReselect: Bool = true, navigator: (Tab) -> Navigator) {
        self.init(selected: selected, tabs: Array(Tab.allCases), popsToRootOnReselect: popsToRootOnReselect, navigator: navigator)
    }
}
