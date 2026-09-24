import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()
    private var stateObserver: DarwinObserver?
    private var heightConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
        inputView = KeyboardInputView(frame: .zero, inputViewStyle: .keyboard)
        model.controller = self

        let host = UIHostingController(rootView: KeyboardView(model: model))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        let height = view.heightAnchor.constraint(equalToConstant: KeyboardMetrics.totalHeight(barExpanded: false))
        height.priority = UILayoutPriority(999)
        heightConstraint = height
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            height,
        ])
        host.didMove(toParent: self)

        // Back Tap can fire while the keyboard is already on screen.
        stateObserver = DarwinObserver(name: AppGroup.stateChanged) { [weak self] in
            self?.model.reloadState()
        }
        trackBarHeight()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.hasFullAccess = hasFullAccess
        model.showsGlobe = needsInputModeSwitchKey
        model.now = Date()
        model.reloadState()
        model.confirmFullAccess()
        model.prepareHaptics()
        model.autoCapitalize()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        model.autoCapitalize()
    }

    /// The keyboard grows by the chip row only while the row has something in it. SwiftUI cannot
    /// resize an input view itself, so follow `barExpanded` and move the height constraint.
    private func trackBarHeight() {
        let expanded = withObservationTracking {
            model.barExpanded
        } onChange: { [weak self] in
            // Fires before the change is applied; read the new value on the next turn.
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.trackBarHeight() } }
        }
        let height = KeyboardMetrics.totalHeight(barExpanded: expanded)
        guard let heightConstraint, heightConstraint.constant != height else { return }
        heightConstraint.constant = height
        guard view.window != nil else { return }
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.view.superview?.layoutIfNeeded()
        }
    }
}

/// Opting in to `UIInputViewAudioFeedback` is what lets `UIDevice.playInputClick()` make the system key click.
final class KeyboardInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}
