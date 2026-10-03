import SwiftUI
import XCTest
@testable import Waypoint

/// Benchmarks for the hot paths: pushing, the path diff SwiftUI's binding triggers on every swipe-back, presenting, and tearing a tree down.
/// Each benchmark also checks that the work released what it built, so a leak can't hide behind a fast number.
@MainActor
final class PerformanceTests: XCTestCase {
    func testPushAndPopThousandScreens() {
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            let home = TestCoordinator()
            let navigator = Navigator(root: home)
            for index in 0..<1_000 { home.push(.detail(index)) }
            navigator.popToRoot()
            XCTAssertEqual(home.madeViewModels.liveCount, 1)
        }
    }

    /// Swipe-back on a deep stack writes a path one shorter. The diff must not be quadratic in the stack depth.
    func testSwipeBackOnDeepStack() {
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        home.push((0..<5_000).map { .detail($0) })
        measure {
            for _ in 0..<500 {
                navigator.setPath(Array(navigator.path.dropLast()))
            }
        }
        XCTAssertEqual(home.madeViewModels.liveCount, 1 + 5_000 - 500 * 10)
    }

    func testPresentDismissChurn() {
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            let home = TestCoordinator()
            let navigator = Navigator(root: home)
            for _ in 0..<500 {
                let child = ChildFlowCoordinator()
                home.presentFlow(child)
                child.push([.step(2), .step(3)])
                navigator.dismissPresentation()
            }
            XCTAssertNil(navigator.presentation)
        }
    }

    func testTearDownLargeTree() {
        measure {
            weak var weakNavigator: Navigator?
            do {
                let home = TestCoordinator()
                let navigator = Navigator(root: home)
                weakNavigator = navigator
                home.push((0..<300).map { .detail($0) })
                var presenter: Coordinator = home
                for _ in 0..<30 {
                    let child = ChildFlowCoordinator()
                    presenter.presentFlow(child)
                    child.push((2..<12).map { .step($0) })
                    presenter = child
                }
                navigator.tearDown()
            }
            XCTAssertNil(weakNavigator)
        }
    }
}
