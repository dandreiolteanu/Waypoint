import SwiftUI
@testable import Waypoint

/// A coordinator whose screens each create a view model that holds the coordinator strongly, the way real screens do.
/// It keeps weak references to every view model it made, so tests can check they were freed.
@MainActor
final class TestCoordinator: FlowCoordinator {
    enum Route: Hashable {
        case home
        case detail(Int)
        case edit(String, onSave: Callback<String>)
        case pick(Callback<Int>)
    }

    let initialRoute: Route
    private(set) var finishCount = 0
    private(set) var madeViewModels = WeakList<TestViewModel>()

    init(initialRoute: Route = .home) {
        self.initialRoute = initialRoute
    }

    override func didFinish() {
        finishCount += 1
    }

    func destination(for route: Route) -> some View {
        let viewModel = TestViewModel(coordinator: self, route: route)
        madeViewModels.append(viewModel)
        return TestScreen(viewModel: viewModel)
    }
}

/// A child flow that returns a value through a callback passed into its `init`, the way real child coordinators report back.
@MainActor
final class ChildFlowCoordinator: FlowCoordinator {
    enum Route: Hashable {
        case step(Int)
    }

    let onComplete: Callback<String>?
    private(set) var finishCount = 0
    private(set) var madeViewModels = WeakList<ChildViewModel>()

    init(onComplete: Callback<String>? = nil) {
        self.onComplete = onComplete
    }

    var initialRoute: Route { .step(1) }

    override func didFinish() {
        finishCount += 1
    }

    func destination(for route: Route) -> some View {
        let viewModel = ChildViewModel(coordinator: self)
        madeViewModels.append(viewModel)
        return ChildScreen(viewModel: viewModel)
    }

    func complete(with value: String) {
        onComplete?(value)
    }
}

@MainActor
final class TestViewModel {
    let coordinator: TestCoordinator
    let route: TestCoordinator.Route

    init(coordinator: TestCoordinator, route: TestCoordinator.Route) {
        self.coordinator = coordinator
        self.route = route
    }
}

@MainActor
final class ChildViewModel {
    let coordinator: ChildFlowCoordinator

    init(coordinator: ChildFlowCoordinator) {
        self.coordinator = coordinator
    }
}

struct TestScreen: View {
    let viewModel: TestViewModel

    var body: some View {
        Text("screen")
    }
}

struct ChildScreen: View {
    let viewModel: ChildViewModel

    var body: some View {
        Text("child")
    }
}

/// Weak references to objects a test wants to watch die.
struct WeakList<Object: AnyObject> {
    private var boxes: [WeakBox] = []

    private struct WeakBox {
        weak var object: Object?
    }

    mutating func append(_ object: Object) {
        boxes.append(WeakBox(object: object))
    }

    var all: [Object?] { boxes.map(\.object) }
    var liveCount: Int { boxes.count { $0.object != nil } }
    var count: Int { boxes.count }
}
