import SwiftUI
import AppKit

/// An NSTextView-backed editor with live SQL syntax highlighting.
struct SQLTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    var fontSize: Double = Double(NSFont.systemFontSize)
    var isEditable: Bool = true

    /// Convenience init so existing call sites that don't need selectedRange compile unchanged.
    init(
        text: Binding<String>,
        selectedRange: Binding<NSRange> = .constant(NSRange()),
        fontSize: Double = Double(NSFont.systemFontSize),
        isEditable: Bool = true
    ) {
        _text = text
        _selectedRange = selectedRange
        self.fontSize = fontSize
        self.isEditable = isEditable
    }

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

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionDidChange(_:)),
            name: NSTextView.didChangeSelectionNotification,
            object: textView
        )

        scrollView.backgroundColor = .textBackgroundColor
        scrollView.drawsBackground = true

        if !text.isEmpty, let storage = textView.textStorage {
            storage.delegate = context.coordinator
            textView.string = text
            SQLHighlighter.highlight(storage, font: editorFont)
        } else {
            textView.textStorage?.delegate = context.coordinator
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
    final class Coordinator: NSObject, NSTextViewDelegate, @preconcurrency NSTextStorageDelegate {
        var parent: SQLTextEditor

        init(_ parent: SQLTextEditor) { self.parent = parent }

        // MARK: - NSTextStorageDelegate

        /// Called from within the text storage editing session (inside endEditing).
        /// Must NOT call beginEditing/endEditing — use incremental highlight path only.
        /// AppKit always calls this on the main thread; @MainActor isolation is safe.
        func textStorage(
            _ textStorage: NSTextStorage,
            willProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            // Only re-highlight when actual characters changed, not attribute-only updates
            // (attribute-only updates come from the highlighter itself — guard prevents re-entry).
            guard editedMask.contains(.editedCharacters) else { return }
            SQLHighlighter.highlightEdited(textStorage, editedRange: editedRange, font: parent.editorFont)
        }

        // MARK: - NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            // Push text change to binding
            parent.text = textView.string
            // Restore base typing attributes so the next inserted character never
            // inherits stale colour from a deleted token. Highlighting was already
            // applied by the NSTextStorageDelegate callback above.
            textView.typingAttributes = parent.baseTypingAttributes
        }

        @objc func selectionDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.selectedRange = textView.selectedRange()
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
