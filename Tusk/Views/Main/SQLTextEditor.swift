import SwiftUI
import AppKit

/// An NSTextView-backed editor with live SQL syntax highlighting.
struct SQLTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.delegate = context.coordinator
        textView.font = editorFont
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.allowsUndo = true

        scrollView.backgroundColor = .textBackgroundColor
        scrollView.drawsBackground = true

        if !text.isEmpty, let storage = textView.textStorage {
            textView.string = text
            SQLHighlighter.highlight(storage, font: editorFont)
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        // Only update when the text changed externally (e.g. tab switch)
        guard textView.string != text, let storage = textView.textStorage else { return }
        let sel = textView.selectedRange()
        textView.string = text
        SQLHighlighter.highlight(storage, font: editorFont)
        let safeLocation = min(sel.location, (text as NSString).length)
        textView.setSelectedRange(NSRange(location: safeLocation, length: 0))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SQLTextEditor

        init(_ parent: SQLTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  let storage = textView.textStorage else { return }
            // Push text change to binding
            parent.text = textView.string
            // Re-apply highlighting, preserving caret position
            let sel = textView.selectedRange()
            SQLHighlighter.highlight(storage, font: parent.editorFont)
            textView.setSelectedRange(sel)
        }
    }

    // MARK: - Helpers

    private var editorFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }
}
