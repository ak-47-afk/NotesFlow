import SwiftUI

/// Renders the AI-generated insights string as a clean bullet list.
/// Strips any leading `**Label**:` or `**Label** -` prefix patterns the AI may have added.
struct InsightsListView: View {
    let insightsText: String

    private var bullets: [String] {
        insightsText
            .components(separatedBy: .newlines)
            .compactMap { line -> String? in
                var text = line.trimmingCharacters(in: .whitespaces)
                if text.isEmpty { return nil }

                // Strip leading bullet markers: "- ", "• ", "* "
                if text.hasPrefix("- ") { text = String(text.dropFirst(2)) }
                else if text.hasPrefix("• ") { text = String(text.dropFirst(2)) }
                else if text.hasPrefix("* ") { text = String(text.dropFirst(2)) }
                if text.isEmpty { return nil }

                // Strip leading **Prefix**: or **Prefix** - patterns
                // e.g. "**Actionable Insight**: The team..." → "The team..."
                let boldPrefixPattern = try? NSRegularExpression(pattern: #"^\*\*[^*]+\*\*\s*[:–-]\s*"#)
                if let match = boldPrefixPattern?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                   let range = Range(match.range, in: text) {
                    text = String(text[range.upperBound...])
                }

                return text.isEmpty ? nil : text
            }
    }

    var body: some View {
        if bullets.isEmpty {
            Text("No insights generated yet.")
                .font(.body)
                .foregroundColor(.secondary)
                .padding(.vertical, 4)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(bullets.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(Color.blue.opacity(0.7))
                            .frame(width: 6, height: 6)
                            .padding(.top, 7)

                        Text(bullets[i])
                            .font(.body)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
