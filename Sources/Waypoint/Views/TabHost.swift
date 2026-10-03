import SwiftUI

/// Builds your `TabView` from a ``TabNavigator``, holding it weakly.
///
/// Use it for every `TabView` driven by a ``TabNavigator``. When the tabs are torn down (``TabNavigator/tearDown()``,
/// on sign-out), `TabHost` renders nothing while it's still mounted, so SwiftUI dismantles the `TabView` properly.
/// A `TabView` removed whole by a root switch can otherwise keep its background tabs' screens, view models and
/// coordinators alive, on some OS versions indefinitely, piling up with every sign-out.
///
/// ```swift
/// TabHost(tabs) { tabs in
///     TabView(selection: tabs.selection) {
///         Tab("Feed", systemImage: "photo", value: AppTab.feed) { NavigationHost(tabs[.feed]) }
///         Tab("Profile", systemImage: "person", value: AppTab.profile) { NavigationHost(tabs[.profile]) }
///     }
/// }
/// ```
public struct TabHost<Tab: Hashable, Content: View>: View {
    private weak var tabs: TabNavigator<Tab>?
    private let content: (TabNavigator<Tab>) -> Content

    /// Shows the tab view `content` builds from `tabs`.
    public init(_ tabs: TabNavigator<Tab>, @ViewBuilder content: @escaping (TabNavigator<Tab>) -> Content) {
        self.tabs = tabs
        self.content = content
    }

    /// Your tab view, while the tabs exist.
    public var body: some View {
        // Once the tabs are torn down, render nothing while this host is still mounted. SwiftUI then dismantles the
        // TabView the normal way. Removed whole by a root switch instead, some OS versions keep its background tabs' last
        // content (and the view models in it) alive indefinitely.
        if let tabs, !tabs.isTornDown {
            content(tabs)
        }
    }
}
