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

    static func highlight(_ textStorage: NSTextStorage, font: NSFont) {
        let text = textStorage.string
        let fullRange = NSRange(location: 0, length: (text as NSString).length)

        // Always bracket with beginEditing/endEditing so the layout manager is
        // notified and the text view can update its insertion-point attributes
        // even when the buffer is empty.
        textStorage.beginEditing()

        if !text.isEmpty {
        // 1. Reset everything to base style
        textStorage.setAttributes([.font: font, .foregroundColor: NSColor.labelColor], range: fullRange)

        // 2. Keywords — lowest priority, overwritten by string / comment passes
        identRE.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let range = match?.range else { return }
            let word = (text as NSString).substring(with: range).uppercased()
            if keywords.contains(word) {
                textStorage.addAttribute(.foregroundColor, value: keywordColour, range: range)
            }
        }

        // 3. Numbers
        colorMatches(of: numberRE, in: text, range: fullRange, color: numberColour, to: textStorage)

        // 4. String literals (override keywords inside strings)
        colorMatches(of: stringRE, in: text, range: fullRange, color: stringColour, to: textStorage)

        // 5. Comments — highest priority, override everything
        colorMatches(of: lineCommentRE,  in: text, range: fullRange, color: commentColour, to: textStorage)
        colorMatches(of: blockCommentRE, in: text, range: fullRange, color: commentColour, to: textStorage)
        } // end if !text.isEmpty

        textStorage.endEditing()
    }

    // MARK: - Helpers

    private static func colorMatches(
        of regex: NSRegularExpression,
        in text: String,
        range: NSRange,
        color: NSColor,
        to textStorage: NSTextStorage
    ) {
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let r = match?.range else { return }
            textStorage.addAttribute(.foregroundColor, value: color, range: r)
        }
    }
}
