import SwiftUI

/// Reports when the presentation containing it has finished animating in.
///
/// SwiftUI's `onAppear` fires when presented content is inserted, at the start of the animation. A presentation started
/// from it can be dropped by UIKit. A child view controller's `viewDidAppear` fires once the transition has completed.
#if os(iOS)
struct PresentationCompletionProbe: UIViewControllerRepresentable {
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> ProbeController {
        ProbeController(onFinish: onFinish)
    }

    func updateUIViewController(_ controller: ProbeController, context: Context) {
        controller.onFinish = onFinish
    }

    final class ProbeController: UIViewController {
        var onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
            view.isHidden = true
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            onFinish()
        }
    }
}
#else
struct PresentationCompletionProbe: View {
    let onFinish: () -> Void

    var body: some View {
        Color.clear.onAppear(perform: onFinish)
    }
}
#endif
