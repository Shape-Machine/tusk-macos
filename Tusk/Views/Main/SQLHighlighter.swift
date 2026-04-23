import AppKit

/// Applies SQL syntax highlighting to an NSTextStorage.
@MainActor
enum SQLHighlighter {

    // MARK: - Token colours

    private static let keywordColour  = NSColor.systemBlue
    private static let commentColour  = NSColor.secondaryLabelColor
    private static let stringColour   = NSColor.systemOrange
    private static let numberColour   = NSColor.systemPurple

    // MARK: - SQL keywords

    private static let keywords: Set<String> = [
        "SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "IN", "IS", "NULL",
        "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE",
        "CREATE", "TABLE", "DROP", "ALTER", "ADD", "COLUMN",
        "INDEX", "UNIQUE", "PRIMARY", "KEY", "FOREIGN", "REFERENCES",
        "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "FULL", "CROSS",
        "ON", "AS", "DISTINCT", "ALL", "ORDER", "BY", "GROUP",
        "HAVING", "LIMIT", "OFFSET", "UNION", "EXCEPT", "INTERSECT",
        "WITH", "RECURSIVE", "CASE", "WHEN", "THEN", "ELSE", "END",
        "IF", "EXISTS", "RETURNING", "CONSTRAINT", "DEFAULT", "SCHEMA",
        "DATABASE", "VIEW", "TRIGGER", "FUNCTION", "PROCEDURE",
        "BEGIN", "COMMIT", "ROLLBACK", "TRANSACTION",
        "TRUE", "FALSE", "BETWEEN", "LIKE", "ILIKE", "SIMILAR",
        "ASC", "DESC", "NULLS", "FIRST", "LAST", "FILTER",
        "OVER", "PARTITION", "WINDOW", "ROWS", "RANGE", "PRECEDING",
        "FOLLOWING", "UNBOUNDED", "CURRENT", "ROW", "CAST", "TYPE",
        "SERIAL", "INTEGER", "BIGINT", "SMALLINT", "TEXT", "VARCHAR",
        "CHAR", "BOOLEAN", "BOOL", "FLOAT", "DOUBLE", "NUMERIC",
        "DECIMAL", "DATE", "TIME", "TIMESTAMP", "INTERVAL", "JSON",
        "JSONB", "UUID", "ARRAY", "OID", "VOID",
    ]

    // MARK: - Cached regexes (static let on @MainActor type is main-actor isolated)

    private static let lineCommentRE  = try! NSRegularExpression(pattern: "--[^\n]*")
    private static let blockCommentRE = try! NSRegularExpression(pattern: "/\\*[\\s\\S]*?\\*/")
    private static let stringRE       = try! NSRegularExpression(pattern: "'(?:[^'\\\\]|\\\\.)*'")
    private static let numberRE       = try! NSRegularExpression(pattern: "\\b\\d+(?:\\.\\d+)?\\b")
    private static let identRE        = try! NSRegularExpression(pattern: "\\b([A-Za-z_][A-Za-z0-9_]*)\\b")

    // MARK: - Public API

    /// Full-document highlight. Wraps in beginEditing/endEditing.
    /// Use for programmatic text replacement (tab switch, font change, initial load).
    static func highlight(_ textStorage: NSTextStorage, font: NSFont) {
        let text = textStorage.string
        let fullRange = NSRange(location: 0, length: text.utf16.count)

        // Always bracket with beginEditing/endEditing so the layout manager is
        // notified and the text view can update its insertion-point attributes
        // even when the buffer is empty.
        textStorage.beginEditing()

        if !text.isEmpty {
            applyHighlighting(to: textStorage, text: text, in: fullRange, font: font)
        }

        textStorage.endEditing()
    }

    /// Incremental highlight called from NSTextStorageDelegate.textStorage(_:willProcessEditing:range:changeInLength:).
    /// Must NOT call beginEditing/endEditing — the text storage is already inside an editing session.
    /// Highlights only the affected paragraph(s), falling back to a full-document pass when
    /// the document contains block comment delimiters (/* or */).
    static func highlightEdited(_ textStorage: NSTextStorage, editedRange: NSRange, font: NSFont) {
        let text = textStorage.string
        guard !text.isEmpty else { return }
        let fullRange = NSRange(location: 0, length: text.utf16.count)

        // Fall back to full-document pass when block comments are present — they can span
        // multiple paragraphs and require whole-document context to highlight correctly.
        let highlightRange: NSRange
        if text.contains("/*") || text.contains("*/") {
            highlightRange = fullRange
        } else {
            highlightRange = (text as NSString).paragraphRange(for: editedRange)
        }

        applyHighlighting(to: textStorage, text: text, in: highlightRange, font: font)
    }

    // MARK: - Internal

    /// Applies syntax highlighting to `range` without begin/endEditing guards.
    private static func applyHighlighting(to textStorage: NSTextStorage, text: String, in range: NSRange, font: NSFont) {
        let fullRange = NSRange(location: 0, length: text.utf16.count)

        // 1. Reset the target range to base style
        textStorage.setAttributes([.font: font, .foregroundColor: NSColor.labelColor], range: range)

        // 2. Keywords — lowest priority, overwritten by string / comment passes
        identRE.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let r = match?.range else { return }
            let word = (text as NSString).substring(with: r).uppercased()
            if keywords.contains(word) {
                textStorage.addAttribute(.foregroundColor, value: keywordColour, range: r)
            }
        }

        // 3. Numbers
        colorMatches(of: numberRE, in: text, range: range, color: numberColour, to: textStorage)

        // 4. Collect string literal ranges (scoped to the highlight range) first; apply their
        //    colour and use them to shield string contents from the comment passes below.
        let stringRanges = collectRanges(of: stringRE, in: text, range: range)
        for r in stringRanges {
            textStorage.addAttribute(.foregroundColor, value: stringColour, range: r)
        }

        // 5. Comments — highest priority, but must not fire inside string literals.
        //    Line comments are always single-line, so the paragraph range is sufficient.
        //    Block comments use the full document range so multi-paragraph spans are caught.
        colorMatches(of: lineCommentRE, in: text, range: range, color: commentColour, to: textStorage, excluding: stringRanges)
        // Block comments require whole-document context — only run on full-document passes.
        // Paragraph-mode calls (from highlightEdited) only reach here when no /* or */ exists,
        // so this pass would match nothing anyway; skip it to avoid an O(doc_size) scan.
        if range == fullRange {
            colorMatches(of: blockCommentRE, in: text, range: fullRange, color: commentColour, to: textStorage, excluding: stringRanges)
        }
    }

    // MARK: - Helpers

    /// Returns all match ranges for `regex` within `range`.
    private static func collectRanges(
        of regex: NSRegularExpression,
        in text: String,
        range: NSRange
    ) -> [NSRange] {
        var ranges: [NSRange] = []
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            if let r = match?.range { ranges.append(r) }
        }
        return ranges
    }

    /// Colours every match of `regex`, skipping any match that overlaps a range in `excluding`.
    private static func colorMatches(
        of regex: NSRegularExpression,
        in text: String,
        range: NSRange,
        color: NSColor,
        to textStorage: NSTextStorage,
        excluding: [NSRange] = []
    ) {
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let r = match?.range else { return }
            if excluding.contains(where: { NSIntersectionRange($0, r).length > 0 }) { return }
            textStorage.addAttribute(.foregroundColor, value: color, range: r)
        }
    }
}
