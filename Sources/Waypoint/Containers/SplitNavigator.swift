import SwiftUI

/// The state behind a `NavigationSplitView`: what's selected in the sidebar, plus a ``Navigator`` (a whole stack) for the
/// detail column, built for each selection.
///
/// ```swift
/// let split = SplitNavigator<Album> { album in
///     Navigator(root: AlbumCoordinator(album: album))
/// }
///
/// SplitHost(split) { split in
///     List(albums, selection: split.selection) { album in
///         Label(album.title, systemImage: album.icon)
///     }
///     .navigationTitle("Albums")
/// } placeholder: {
///     ContentUnavailableView("Pick an album", systemImage: "photo.on.rectangle")
/// }
/// ```
///
/// On iPad the sidebar and detail sit side by side. In compact width (iPhone, Slide Over) the split view collapses into
/// one stack: picking a row pushes its detail, and going back clears the selection. Changing the selection tears the old
/// detail flow down, so its coordinators and view models are freed.
@MainActor
@Observable
public final class SplitNavigator<Selection: Hashable> {
    /// The selected sidebar item, if any.
    public private(set) var selected: Selection?
    /// The navigator showing the selected item, if any.
    public private(set) var detail: Navigator?
    /// Which columns are visible. Bind it, or set it, to show or hide the sidebar.
    public var columnVisibility: NavigationSplitViewVisibility
    @ObservationIgnored private let makeDetail: (Selection) -> Navigator
    private(set) var isTornDown = false

    /// - Parameters:
    ///   - selected: The item selected at first, if any. On iPad, select something so the detail column isn't empty.
    ///   - columnVisibility: Which columns are visible at first.
    ///   - detail: Builds the detail navigator for a selection. It's called each time the selection changes.
    public init(
        selected: Selection? = nil,
        columnVisibility: NavigationSplitViewVisibility = .automatic,
        detail: @escaping (Selection) -> Navigator
    ) {
        self.makeDetail = detail
        self.columnVisibility = columnVisibility
        if let selected {
            self.selected = selected
            self.detail = detail(selected)
        }
    }

    /// The binding for `List(selection:)` in the sidebar.
    public var selection: Binding<Selection?> {
        // Weak, so a split view SwiftUI keeps around after a root switch doesn't keep the flows alive.
        Binding(get: { [weak self] in self?.selected }, set: { [weak self] in self?.select($0) })
    }

    /// Selects `item` from code, building its detail flow. Selecting the current item again keeps its flow as it is.
    /// Pass `reset: true` to dismiss the detail's sheets and pop it to its root instead, as a deep link usually wants.
    public func select(_ item: Selection?, reset: Bool = false) {
        guard !isTornDown else { return }
        if item == selected {
            if reset { detail?.reset() }
            return
        }
        detail?.tearDown()
        selected = item
        detail = item.map(makeDetail)
    }

    /// The coordinator at the root of the detail column, as `C`. Reach the detail flow for a deep link:
    /// `split.detailCoordinator(as: AlbumCoordinator.self)?.showPhoto(id)`.
    public func detailCoordinator<C: Coordinator>(as type: C.Type) -> C? {
        detail?.rootCoordinator(as: type)
    }

    /// Ends the detail flow and releases it. Call it when you discard the split view, on sign-out for example.
    public func tearDown() {
        guard !isTornDown else { return }
        isTornDown = true
        detail?.tearDown()
        detail = nil
    }
}

/// Shows a ``SplitNavigator`` as a `NavigationSplitView`, holding it weakly.
///
/// You build the sidebar. Bind its `List` to ``SplitNavigator/selection``. The detail column shows the selected item's
/// navigator, or `placeholder` when nothing is selected.
public struct SplitHost<Selection: Hashable, Sidebar: View, Placeholder: View>: View {
    private weak var split: SplitNavigator<Selection>?
    private let sidebar: (SplitNavigator<Selection>) -> Sidebar
    private let placeholder: () -> Placeholder

    /// Shows `split`, with a sidebar built by `sidebar`, and `placeholder` in the detail column while nothing is selected.
    public init(
        _ split: SplitNavigator<Selection>,
        @ViewBuilder sidebar: @escaping (SplitNavigator<Selection>) -> Sidebar,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.split = split
        self.sidebar = sidebar
        self.placeholder = placeholder
    }

    /// The split view, while the split navigator exists and isn't torn down.
    public var body: some View {
        if let split, !split.isTornDown {
            NavigationSplitView(columnVisibility: Binding(
                get: { [weak split] in split?.columnVisibility ?? .automatic },
                set: { [weak split] in split?.columnVisibility = $0 }
            )) {
                sidebar(split)
            } detail: {
                if let detail = split.detail {
                    NavigationHost(detail)
                        // A new selection is a new flow: a fresh stack, not the old one's path.
                        .id(ObjectIdentifier(detail))
                } else {
                    placeholder()
                }
            }
        }
    }
}
