import Foundation

/// Builds a focused source snippet around a target line while keeping output
/// compact and readable.
public enum SnippetBuilder {
    /// Returns a source snippet around `line` with a bounded line count.
    ///
    /// The snippet size is clamped to 20~40 lines when the file is large
    /// enough, with a default target of 30 lines.
    public static func around(
        text: String,
        line: Int?,
        targetLines: Int = 30,
        minLines: Int = 20,
        maxLines: Int = 40
    ) -> String? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard !lines.isEmpty else { return nil }

        let total = lines.count
        let clampedTarget = min(max(targetLines, minLines), maxLines)
        let snippetSize: Int
        if total >= minLines {
            snippetSize = min(total, clampedTarget)
        } else {
            snippetSize = total
        }

        let centerLine = min(max(line ?? 1, 1), total)
        var start = max(1, centerLine - (snippetSize / 2))
        var end = start + snippetSize - 1
        if end > total {
            end = total
            start = max(1, end - snippetSize + 1)
        }

        return lines[(start - 1)...(end - 1)].joined(separator: "\n")
    }

    /// Converts a UTF-16 offset to a one-based source line number.
    public static func lineNumber(in text: String, utf16Offset: Int) -> Int {
        let safeOffset = min(max(utf16Offset, 0), text.utf16.count)
        let idx = String.Index(utf16Offset: safeOffset, in: text)
        return text[..<idx].reduce(into: 1) { partial, ch in
            if ch == "\n" { partial += 1 }
        }
    }
}
