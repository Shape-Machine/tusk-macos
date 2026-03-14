import SwiftUI
import AppKit

extension View {
    /// Instructs the enclosing VSplitView to persist its divider position
    /// across app launches using AppKit's built-in autosave mechanism.
    /// Apply to any direct child of the VSplitView.
    func splitViewAutosaveName(_ name: String) -> some View {
        background(SplitViewAutosaveConfigurator(autosaveName: name))
    }
}

// MARK: - Implementation

private struct SplitViewAutosaveConfigurator: NSViewRepresentable {
    let autosaveName: String

    func makeNSView(context: Context) -> SplitViewFinderView {
        SplitViewFinderView(autosaveName: autosaveName)
    }

    func updateNSView(_ nsView: SplitViewFinderView, context: Context) {}
}

private final class SplitViewFinderView: NSView {
    let autosaveName: String

    init(autosaveName: String) {
        self.autosaveName = autosaveName
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        // Defer one run loop pass to let SwiftUI finish building
        // the view hierarchy before we walk it.
        DispatchQueue.main.async { [weak self] in
            self?.configureSplitView()
        }
    }

    private func configureSplitView() {
        var current: NSView? = superview
        while let v = current {
            if let splitView = v as? NSSplitView {
                splitView.autosaveName = autosaveName
                return
            }
            current = v.superview
        }
    }
}
