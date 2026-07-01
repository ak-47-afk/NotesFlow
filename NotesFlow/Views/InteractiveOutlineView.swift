import SwiftUI

struct InteractiveOutlineSection: Identifiable {
    var id = UUID()
    var title: String
    var points: [InteractiveOutlinePoint]
}

struct InteractiveOutlinePoint: Identifiable {
    var id = UUID()
    var text: String
}

// MARK: - Markdown Text Helper

/// Renders a string with inline markdown (bold, italic) using AttributedString.
/// Falls back to plain Text if parsing fails.
private func markdownText(_ raw: String) -> Text {
    if let attributed = try? AttributedString(
        markdown: raw,
        options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    ) {
        return Text(attributed)
    }
    return Text(raw)
}

// MARK: - Editable Bullet Point Row

private struct BulletPointRow: View {
    @Binding var point: InteractiveOutlinePoint
    var onDelete: () -> Void
    var onSave: () -> Void

    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(.secondary)
                .padding(.top, 4)

            if isEditing {
                TextField("Point detail", text: $point.text, axis: .vertical)
                    .font(.body)
                    .textFieldStyle(.plain)
                    .lineSpacing(3)
                    .focused($isFocused)
                    .onSubmit {
                        isEditing = false
                        onSave()
                    }
                    .onChange(of: isFocused) { _, focused in
                        if !focused {
                            isEditing = false
                            onSave()
                        }
                    }
                    .onAppear { isFocused = true }
            } else {
                markdownText(point.text)
                    .font(.body)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { isEditing = true }
            }

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .opacity(0.5)
        }
    }
}

// MARK: - Main Outline View

struct InteractiveOutlineView: View {
    @Binding var outlineText: String
    @State private var sections: [InteractiveOutlineSection] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if outlineText == "Generating outline..." {
                Text("Generating outline...")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach($sections) { $section in
                VStack(alignment: .leading, spacing: 10) {
                    // Section title — use plain TextField (headers rarely contain markdown)
                    TextField("Section Title", text: $section.title)
                        .font(.headline)
                        .textFieldStyle(.plain)
                        .padding(.vertical, 4)
                        .onChange(of: section.title) { _, _ in saveToText() }

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach($section.points) { $point in
                            BulletPointRow(
                                point: $point,
                                onDelete: {
                                    if let idx = section.points.firstIndex(where: { $0.id == point.id }) {
                                        section.points.remove(at: idx)
                                        saveToText()
                                    }
                                },
                                onSave: { saveToText() }
                            )
                        }

                        Button(action: {
                            section.points.append(InteractiveOutlinePoint(text: ""))
                            saveToText()
                        }) {
                            Text("+ Add detail")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 14)
                    }
                }
            }

            Button(action: {
                sections.append(InteractiveOutlineSection(title: "New Section", points: [InteractiveOutlinePoint(text: "")]))
                saveToText()
            }) {
                Label("Add outline section", systemImage: "plus")
                    .foregroundColor(.blue)
                    .font(.subheadline.bold())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            } // Close else
        }
        .onAppear {
            parseText()
        }
        .onChange(of: outlineText) { _, newValue in
            // Only re-parse if the text was changed externally (e.g. newly generated by AI)
            let generatedText = generateText()
            if newValue != generatedText {
                parseText()
            }
        }
    }

    private func parseText() {
        var newSections: [InteractiveOutlineSection] = []
        let lines = outlineText.components(separatedBy: .newlines)
        var currentSection: InteractiveOutlineSection?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if isHeader(trimmed) {
                if let cs = currentSection { newSections.append(cs) }
                currentSection = InteractiveOutlineSection(title: cleanHeader(trimmed), points: [])
            } else {
                if currentSection == nil {
                    currentSection = InteractiveOutlineSection(title: "General", points: [])
                }
                // Preserve the raw text including any **bold** markers so markdownText() can render them
                currentSection?.points.append(InteractiveOutlinePoint(text: cleanBullet(trimmed)))
            }
        }
        if let cs = currentSection { newSections.append(cs) }

        self.sections = newSections
    }

    private func saveToText() {
        outlineText = generateText()
    }

    private func generateText() -> String {
        var output = ""
        for section in sections {
            if !section.title.isEmpty {
                output += "## \(section.title)\n"
            }
            for point in section.points {
                if !point.text.isEmpty {
                    output += "- \(point.text)\n"
                }
            }
            output += "\n"
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isHeader(_ line: String) -> Bool {
        if line.hasPrefix("##") || line.hasPrefix("#") { return true }
        // A line starting with ** and ending with ** is a bold header, not a bullet
        if line.hasPrefix("**") && line.hasSuffix("**") && !line.hasPrefix("- ") { return true }
        if line.first?.isNumber == true && line.contains(".") && !line.hasPrefix("-") && line.count < 80 { return true }
        if !line.hasPrefix("-") && !line.hasPrefix("*") && !line.hasPrefix("•") && line.count < 60 { return true }
        return false
    }

    private func cleanHeader(_ line: String) -> String {
        var cleaned = line
        cleaned = cleaned.replacingOccurrences(of: "###", with: "")
        cleaned = cleaned.replacingOccurrences(of: "##", with: "")
        cleaned = cleaned.replacingOccurrences(of: "#", with: "")
        // Strip surrounding ** from header-level bold (e.g. **Section Name**)
        if cleaned.hasPrefix("**") && cleaned.hasSuffix("**") {
            cleaned = String(cleaned.dropFirst(2).dropLast(2))
        }
        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    private func cleanBullet(_ line: String) -> String {
        var cleaned = line
        if cleaned.hasPrefix("- ") { cleaned = String(cleaned.dropFirst(2)) }
        if cleaned.hasPrefix("* ") { cleaned = String(cleaned.dropFirst(2)) }
        if cleaned.hasPrefix("• ") { cleaned = String(cleaned.dropFirst(2)) }
        // Do NOT strip ** here — preserve them so markdownText() renders bold correctly
        return cleaned.trimmingCharacters(in: .whitespaces)
    }
}
