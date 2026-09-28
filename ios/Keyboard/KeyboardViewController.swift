import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()
    private var stateObserver: DarwinObserver?
    private var heightConstraint: NSLayoutConstraint?
    private var diagnostics: KeyboardDiagnostics?

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
        #if DEBUG
        simulatedBackTapObserver = DarwinObserver(name: AppGroup.simulatedBackTap) {
            Self.runSimulatedBackTap()
        }
        #endif
    }

    #if DEBUG
    private var simulatedBackTapObserver: DarwinObserver?

    /// The Simulator has no Back Tap and no Shortcuts app. `tools/simulate-back-tap.sh` drops a screenshot
    /// into the App Group and posts `AppGroup.simulatedBackTap`; this runs the same analysis the intent would.
    private static func runSimulatedBackTap() {
        guard let url = SharedStore.containerURL?.appendingPathComponent("simulated-back-tap.jpg"),
              let data = try? Data(contentsOf: url)
        else { return }
        Task { try? await ChatAnalysisService.run(imageData: data, fromShortcut: false) }
    }
    #endif

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.hasFullAccess = hasFullAccess
        model.showsGlobe = needsInputModeSwitchKey
        model.now = Date()
        model.reloadState()
        model.scheduleRefresh()
        model.confirmFullAccess()
        model.prepareHaptics()
        model.autoCapitalize()
        startDiagnostics()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        model.stopRefresh()
        finishDiagnostics()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        diagnostics?.memoryWarning()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        model.autoCapitalize()
    }

    // MARK: Diagnostics

    /// One session per appearance, only while the app's Diagnostika switch is on. Needs Full Access: without it
    /// the keyboard cannot write to the App Group.
    private func startDiagnostics() {
        finishDiagnostics()
        guard hasFullAccess, model.state.diagnosticsEnabled == true else { return }
        let session = KeyboardDiagnostics(testMode: isDiagnosticsTestField)
        diagnostics = session
        model.diagnostics = session
    }

    private func finishDiagnostics() {
        guard let session = diagnostics else { return }
        diagnostics = nil
        model.diagnostics = nil
        let result = session.finish()
        // A keyboard that flashed up and away tells nothing.
        guard result.duration >= 1 else { return }
        DispatchQueue.global(qos: .utility).async {
            DiagnosticsStore.append(result)
            DarwinNotification.post(AppGroup.diagnosticsChanged)
        }
    }

    /// The app's typing-test field marks itself; only there does the journal keep individual touches.
    private var isDiagnosticsTestField: Bool {
        let contentType: UITextContentType? = textDocumentProxy.textContentType ?? nil
        if contentType?.rawValue == DiagnosticsMarker.contentType { return true }
        // In case iOS does not hand a custom content type to the keyboard: a trait pair no chat field uses.
        return textDocumentProxy.keyboardType == UIKeyboardType.asciiCapable
            && textDocumentProxy.returnKeyType == UIReturnKeyType.continue
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
