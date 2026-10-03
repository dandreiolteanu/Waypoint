import Foundation

/// Debug-only bookkeeping of live navigation objects, for spotting leaks.
///
/// Waypoint tracks its own coordinators, navigators and entries. Call ``track(_:kind:)`` from your view models' `init` to include them too.
/// After the user leaves a flow, ``liveCount(of:)`` should drop back to where it was. The example app shows these counts in an overlay,
/// and its UI tests assert on them. In release builds tracking is compiled out and every query returns zero.
@MainActor
public enum LifetimeTracker {
    /// The categories counted separately.
    public enum Kind: String, CaseIterable, Sendable {
        /// Waypoint coordinators. Tracked automatically.
        case coordinator
        /// Waypoint navigators. Tracked automatically.
        case navigator
        /// Screens in navigation state. Tracked automatically.
        case entry
        /// Your view models, or anything else you register with ``LifetimeTracker/track(_:kind:)``.
        case viewModel
    }

    private struct Record {
        weak var object: AnyObject?
        let kind: Kind
        let typeName: String
    }

    #if DEBUG
    private static var records: [Record] = []
    /// Dead records are swept when the list doubles, which keeps `track` amortized O(1).
    private static var sweepThreshold = 64
    #endif

    /// Starts counting `object` until it's freed. Cheap, and does nothing in release builds.
    ///
    /// ```swift
    /// init(...) { LifetimeTracker.track(self, kind: .viewModel) }
    /// ```
    public static func track(_ object: AnyObject, kind: Kind) {
        #if DEBUG
        if records.count >= sweepThreshold {
            records.removeAll { $0.object == nil }
            sweepThreshold = max(64, records.count * 2)
        }
        records.append(Record(object: object, kind: kind, typeName: String(describing: type(of: object))))
        #endif
    }

    /// The number of tracked objects of `kind` that are still alive.
    public static func liveCount(of kind: Kind) -> Int {
        #if DEBUG
        records.lazy.filter { $0.kind == kind && $0.object != nil }.count
        #else
        0
        #endif
    }

    /// The type names of the tracked objects that are still alive, optionally filtered by kind. Sorted, with duplicates kept.
    public static func liveTypeNames(of kind: Kind? = nil) -> [String] {
        #if DEBUG
        records.filter { $0.object != nil && (kind == nil || $0.kind == kind) }.map(\.typeName).sorted()
        #else
        []
        #endif
    }
}
