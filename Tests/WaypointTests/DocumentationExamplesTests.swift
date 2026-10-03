import SwiftUI
import Testing
@testable import Waypoint

// The code samples from the documentation, compiled and exercised, so the docs can't drift from the API.

// MARK: - Overview and Testing article: LibraryCoordinator

struct Book: Identifiable, Hashable {
    let id: Int
    var title = "Untitled"
}

@MainActor
final class LibraryCoordinator: FlowCoordinator {
    enum Route: Hashable {
        case shelf
        case book(Book.ID)
        case rename(current: String, onSave: Callback<String>)
        case filters
    }

    var initialRoute: Route { .shelf }

    func destination(for route: Route) -> some View {
        switch route {
        case .shelf: Text("Shelf").onTapGesture { self.open(Book(id: 1)) }
        case .book(let id): Text("Book \(id)")
        case .rename(let current, let onSave): Button(current) { onSave("Renamed") }
        case .filters: Text("Filters")
        }
    }

    func open(_ book: Book) {
        push(.book(book.id), transition: .zoom(sourceID: book.id))
    }

    func rename(_ book: Book) async -> String? {
        await present(as: .sheet(detents: [.medium])) { .rename(current: book.title, onSave: $0) }
    }

    func showFilters() {
        present(.filters, as: .sheet(detents: [.medium, .large]))
    }
}

// MARK: - Passing Data article: a flow sharing a draft, returning a value

@MainActor @Observable
final class SignUpDraft {
    var name = ""
}

@MainActor
final class SignUpCoordinator: FlowCoordinator {
    enum Route: Hashable { case name, summary }

    private let draft = SignUpDraft()
    private let onComplete: Callback<String>

    init(onComplete: Callback<String>) {
        self.onComplete = onComplete
    }

    var initialRoute: Route { .name }

    func destination(for route: Route) -> some View {
        switch route {
        case .name: Text("Name")
        case .summary: Text("Summary")
        }
    }

    func enter(name: String) {
        draft.name = name
        push(.summary)
    }

    func finishSignUp() {
        onComplete(draft.name)
    }
}

@MainActor
@Suite("Documentation examples")
struct DocumentationExamplesTests {
    @Test("Overview: open a book, then rename it through an awaited sheet")
    func overview() async throws {
        let library = LibraryCoordinator()
        let navigator = Navigator(root: library)

        library.open(Book(id: 42))
        #expect(library.routes == [.shelf, .book(42)])

        let task = Task { await library.rename(Book(id: 1, title: "Old")) }
        await settle()
        let route = try #require(library.presented?.route(as: LibraryCoordinator.Route.self))
        guard case .rename(_, let onSave) = route else {
            Issue.record("Expected the rename sheet")
            return
        }
        #expect(library.presented?.selectedDetent == .medium)
        onSave("New")

        #expect(await task.value == "New")
        #expect(navigator.presentation == nil)
    }

    @Test("Testing article: filters open as a medium sheet")
    func filters() {
        let library = LibraryCoordinator()
        let navigator = Navigator(root: library)

        library.showFilters()

        #expect(library.presented?.route(as: LibraryCoordinator.Route.self) == .filters)
        #expect(library.presented?.selectedDetent == .medium)
        #expect(navigator.topRoute(as: LibraryCoordinator.Route.self) == .shelf)
    }

    @Test("Passing Data: a presented flow shares a draft and returns its value")
    func signUpFlow() async throws {
        let library = LibraryCoordinator()
        let navigator = Navigator(root: library)
        weak var weakFlow: SignUpCoordinator?
        let task = Task {
            await library.presentFlow(as: .fullScreenCover) { onComplete in
                let flow = SignUpCoordinator(onComplete: onComplete)
                weakFlow = flow
                return flow
            }
        }
        await settle()
        let flow = try #require(weakFlow)

        flow.enter(name: "Ada")
        #expect(navigator.presentation?.topRoute(as: SignUpCoordinator.Route.self) == .summary)
        flow.finishSignUp()

        #expect(await task.value == "Ada")
        #expect(navigator.presentation == nil)
    }

    @Test("Tabs and Deep Links: build tabs exhaustively, reach a tab's coordinator, reset for a link")
    func tabsAndDeepLinks() {
        enum AppTab: Hashable, CaseIterable { case library, settings }

        let tabs = TabNavigator(selected: AppTab.library) { tab in
            switch tab {
            case .library: Navigator(root: LibraryCoordinator())
            case .settings: Navigator(root: TestCoordinator())
            }
        }
        tabs.coordinator(for: .library, as: LibraryCoordinator.self)?.showFilters()
        tabs.select(.settings)

        // A deep link into the library tab: clean slate, then navigate.
        tabs.select(.library, reset: true)
        tabs.coordinator(for: .library, as: LibraryCoordinator.self)?.open(Book(id: 7))

        #expect(tabs.selectedTab == .library)
        #expect(tabs[.library].presentation == nil)
        #expect(tabs.coordinator(for: .library, as: LibraryCoordinator.self)?.routes == [.shelf, .book(7)])
    }

    @Test("Deep Links: start a flow a few screens deep")
    func pushFlowThen() {
        let home = TestCoordinator()
        let navigator = Navigator(root: home)

        home.pushFlow(ChildFlowCoordinator(), then: [.step(2), .step(3)])

        #expect(navigator.depth == 3)
        #expect(navigator.topRoute(as: ChildFlowCoordinator.Route.self) == .step(3))
    }

    @Test("Alerts: confirm and choose")
    func alerts() async throws {
        enum ExportFormat: Sendable { case pdf, png }
        let library = LibraryCoordinator()
        let navigator = Navigator(root: library)

        let confirmed = Task { await library.confirm("Sign out?", confirmTitle: "Sign out", role: .destructive) }
        await settle()
        navigator.finishAlert(try #require(navigator.alertRequest), choosing: 0)
        #expect(await confirmed.value)

        let format = Task {
            await library.alert("Export as", style: .confirmationDialog, actions: [
                AlertAction("PDF", value: ExportFormat.pdf),
                AlertAction("PNG", value: ExportFormat.png)
            ])
        }
        await settle()
        navigator.finishAlert(try #require(navigator.alertRequest), choosing: 1)
        #expect(await format.value == .png)
    }

    @Test("Getting Started: NavigationHost(root:) builds its navigator only once")
    func hostBuildsOnce() {
        var made = 0
        let host = NavigationHost(root: { () -> LibraryCoordinator in
            made += 1
            return LibraryCoordinator()
        }())
        #expect(made == 0, "The root coordinator is built lazily, when the host first renders")
        _ = host
    }

    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }
}
