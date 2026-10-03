import SwiftUI

/// Builds your `TabView` from a ``TabNavigator``, holding it weakly.
///
/// SwiftUI can keep a removed `TabView` alive for a while after a root switch. `TabHost` (with ``TabNavigator/tearDown()``)
/// makes sure what it keeps is empty, so a signed-out user's tabs, coordinators and view models are freed.
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
        if let tabs {
            content(tabs)
        }
    }
}
