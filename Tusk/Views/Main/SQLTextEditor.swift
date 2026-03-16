import SwiftUI
import AppKit

/// An NSTextView-backed editor with live SQL syntax highlighting.
struct SQLTextEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: Double = Double(NSFont.systemFontSize)
    var isEditable: Bool = true

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.delegate = context.coordinator
        textView.font = editorFont
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.isEditable = isEditable
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
        textView.typingAttributes = baseTypingAttributes

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = nsView.documentView as? NSTextView else { return }
        // Re-apply font if it changed (e.g. user adjusted content font size setting)
        if textView.font != editorFont, let storage = textView.textStorage {
            textView.font = editorFont
            SQLHighlighter.highlight(storage, font: editorFont)
            textView.typingAttributes = baseTypingAttributes
        }
        // Only update text when it changed externally (e.g. tab switch)
        guard textView.string != text, let storage = textView.textStorage else { return }
        let sel = textView.selectedRange()
        textView.string = text
        SQLHighlighter.highlight(storage, font: editorFont)
        textView.typingAttributes = baseTypingAttributes
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
            // Always restore base typing attributes so the next inserted
            // character never inherits stale colour from a deleted token.
            textView.typingAttributes = parent.baseTypingAttributes
            textView.setSelectedRange(sel)
        }
    }

    // MARK: - Helpers

    var editorFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    var baseTypingAttributes: [NSAttributedString.Key: Any] {
        [.font: editorFont, .foregroundColor: NSColor.labelColor]
    }
}
