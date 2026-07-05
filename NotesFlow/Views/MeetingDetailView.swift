import SwiftUI
import SwiftData

struct MeetingDetailView: View {
    @Bindable var meeting: Meeting
    
    @Environment(\.modelContext) private var modelContext
    @Environment(AIService.self) private var aiservice
    @Environment(TranscriptionService.self) private var transcriptionService
    @Environment(WhisperTranscriptionService.self) private var whisperService
    @Environment(AudioRecorderService.self) private var audioService
    
    @State private var selectedTab = "Summary"
    @State private var searchText = ""
    @State private var showSourcePicker = false
    @State private var isChatSidebarVisible = true
    
    @Query private var templates: [SummaryTemplate]
    
    var body: some View {
        if meeting.isDeleted {
            ContentUnavailableView("Meeting Deleted", systemImage: "trash")
        } else {
            HStack(spacing: 0) {
            VStack(spacing: 0) {
                // Search Bar in Middle Section
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Search this meeting...", text: $searchText)
                        .textFieldStyle(.plain)
                    Text("⌘ F").font(.caption).foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.gray.opacity(0.2), lineWidth: 1))
                .padding(.horizontal, 24)
                .padding(.top, 16)
                
                // Header
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        TextField("Meeting Title", text: $meeting.title)
                            .font(.title.bold())
                            .textFieldStyle(.plain)
                        Spacer()
                        
                        HStack(spacing: 8) {
                            Menu {
                                Button("Share Summary", action: shareSummary)
                                Button("Share Transcript", action: shareTranscript)
                                Button("Share Recording", action: shareRecording)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Share")
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            

                            
                            Menu {
                                Button("Regenerate Summary", systemImage: "arrow.clockwise") {
                                    regenerateSummary()
                                }
                                Button("Regenerate Transcription", systemImage: "waveform") {
                                    regenerateTranscription()
                                }
                                .disabled(whisperService.isTranscribing || transcriptionService.isTranscribing)
                                Button("Delete Meeting", systemImage: "trash", role: .destructive) {
                                    modelContext.delete(meeting)
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.gray.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
                    }
                    .zIndex(1)
                    
                    HStack(spacing: 15) {
                        Label(meeting.date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                        Label(meeting.duration, systemImage: "clock")
                        
                        Button(action: { showSourcePicker.toggle() }) {
                            Label(meeting.source, systemImage: sourceIcon(for: meeting.source))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showSourcePicker, arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Update Source").font(.caption).foregroundColor(.secondary)
                                ForEach(["Zoom", "Google Meet", "Microsoft Teams", "Slack Huddle", "In Person", "Uploaded Audio"], id: \.self) { source in
                                    Button(source) {
                                        meeting.source = source
                                        showSourcePicker = false
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.vertical, 4)
                                }
                            }
                            .padding()
                            .frame(width: 150)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                
                // Tabs
                HStack(spacing: 0) {
                    ForEach(["Summary", "Transcript", "Notes"], id: \.self) { tab in
                        Button(action: { withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab } }) {
                            Text(tab)
                                .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                                .foregroundColor(selectedTab == tab ? .primary : .secondary)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 16)
                                .overlay(alignment: .bottom) {
                                    if selectedTab == tab {
                                        Rectangle()
                                            .fill(Color.blue)
                                            .frame(height: 2)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    
                    if selectedTab == "Summary" {
                        Menu {
                            let currentTemplate = meeting.summary?.templateName ?? "Default Built-In"
                            Button {
                                regenerateSummary(with: nil)
                            } label: {
                                HStack {
                                    Text("Default Built-In")
                                    if currentTemplate == "Default Built-In" {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            if !templates.isEmpty {
                                Divider()
                            }
                            ForEach(templates) { template in
                                Button {
                                    regenerateSummary(with: template)
                                } label: {
                                    HStack {
                                        Text(template.title)
                                        if currentTemplate == template.title {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("Template")
                                Image(systemName: "chevron.down")
                            }
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 120)
                    }
                }
                .padding(.horizontal, 24)
                .background(Color(NSColor.textBackgroundColor))
                
                Divider()
                
                // Tab Content
                Group {
                    switch selectedTab {
                    case "Summary":
                        SummaryView(meeting: meeting, aiservice: aiservice)
                    case "Transcript":
                        TranscriptView(meeting: meeting)
                    case "Notes":
                        NotesView(meeting: meeting)
                    default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    FloatingAudioPlayer(meeting: meeting, audioService: audioService)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            if isChatSidebarVisible {
                Divider()
                MeetingChatView(meeting: meeting, aiservice: aiservice)
                    .transition(.move(edge: .trailing))
            }
        }
        }
    }
    
    private func sourceIcon(for source: String) -> String {
        switch source {
        case "Zoom": return "video"
        case "Google Meet": return "video.fill"
        case "Microsoft Teams": return "person.3.fill"
        case "Slack Huddle": return "headphones"
        case "Uploaded Audio": return "waveform"
        case "In Person": return "person.2"
        default: return "mic"
        }
    }
    
    private func regenerateSummary(with template: SummaryTemplate? = nil) {
        let transcriptText = meeting.transcript.map { $0.text }.joined(separator: " ")
        guard !transcriptText.isEmpty else { return }
        
        aiservice.isProcessing = true
        
        if let existingSummary = meeting.summary {
            existingSummary.overview = "Generating overview..."
            existingSummary.keyDecisions = "Generating key decisions..."
            existingSummary.openQuestions = "Generating open questions..."
            existingSummary.insights = "Generating insights..."
            existingSummary.outline = "Generating outline..."
        } else {
            let tempSummary = Summary(overview: "Generating overview...", insights: "Generating insights...", outline: "Generating outline...", keyDecisions: "Generating key decisions...", openQuestions: "Generating open questions...", attendees: [], templateName: template?.title ?? "Default Built-In")
            meeting.summary = tempSummary
            modelContext.insert(tempSummary)
        }
        
        aiservice.generateSummary(transcript: transcriptText, using: template, onFastResult: { fastResult in
            meeting.title = fastResult.title != "New Meeting" ? fastResult.title : meeting.title
            let usedTemplateName = template?.title ?? "Default Built-In"
            
            if let existingSummary = meeting.summary {
                existingSummary.overview = fastResult.overview
                existingSummary.keyDecisions = fastResult.keyDecisions
                existingSummary.openQuestions = fastResult.openQuestions
                existingSummary.attendees = fastResult.attendees
                existingSummary.templateName = usedTemplateName
            } else {
                let newSummary = Summary(overview: fastResult.overview, insights: "Generating insights...", outline: "Generating outline...", keyDecisions: fastResult.keyDecisions, openQuestions: fastResult.openQuestions, attendees: fastResult.attendees, templateName: usedTemplateName)
                meeting.summary = newSummary
                modelContext.insert(newSummary)
            }
            
            // Delete old action items
            meeting.actionItems.forEach { modelContext.delete($0) }
            meeting.actionItems.removeAll()
            
            // Insert new action items
            for item in fastResult.actionItems {
                let actionItem = ActionItem(task: "[\(item.speaker)] \(item.task)", isCompleted: false)
                meeting.actionItems.append(actionItem)
                modelContext.insert(actionItem)
            }
        }, onOutlineStream: { partialOutline in
            meeting.summary?.outline = partialOutline
        }, onInsightsComplete: { fullInsights in
            meeting.summary?.insights = fullInsights
        }, onComplete: { success in
            aiservice.isProcessing = false
            if success {
                NotificationManager.shared.sendNotification(title: "Summary Regenerated", body: "The summary for '\(meeting.title)' is ready.")
            }
        }, onError: { errorMsg in
            AppLogger.error("Summary regeneration error: \(errorMsg)")
            if meeting.summary?.insights == "Generating insights..." {
                meeting.summary?.insights = "Error: \(errorMsg)"
            }
            if meeting.summary?.outline == "Generating outline..." {
                meeting.summary?.outline = ""
            }
            if meeting.summary?.keyDecisions == "Generating key decisions..." {
                meeting.summary?.keyDecisions = ""
            }
            if meeting.summary?.openQuestions == "Generating open questions..." {
                meeting.summary?.openQuestions = ""
            }
            if meeting.summary?.overview == "Generating overview..." {
                meeting.summary?.overview = ""
            }
            aiservice.isProcessing = false
        })
    }
    
    private func regenerateTranscription() {
        guard let url = meeting.audioURL else { return }
        
        Task {
            do {
                whisperService.currentTranscribingMeetingId = meeting.id
                meeting.transcript.removeAll()
                
                let segments = try await whisperService.transcribe(audioURL: url)
                
                for (index, seg) in segments.enumerated() {
                    let ts = TranscriptSegment(text: seg.text, timestamp: seg.timestamp, speaker: seg.speaker)
                    ts.meeting = meeting
                    modelContext.insert(ts)
                    meeting.transcript.append(ts)
                }
                
                regenerateSummary()
            } catch {
                print("Failed to regenerate transcription: \(error)")
                Task { @MainActor in
                    whisperService.isTranscribing = false
                }
            }
        }
    }

    private func shareSummary() {
        let text = meeting.summary?.overview ?? "No summary available."
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    private func shareTranscript() {
        let text = meeting.transcript.map { "[\(formatTime($0.timestamp))] \($0.text)" }.joined(separator: "\n\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    private func shareRecording() {
        guard let url = meeting.audioURL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSPasteboardWriting])
    }
    
    private func formatTime(_ ts: TimeInterval) -> String {
        let min = Int(ts) / 60
        let sec = Int(ts) % 60
        return String(format: "%02d:%02d", min, sec)
    }
}

// MARK: - Summary View
struct SummaryView: View {
    @Bindable var meeting: Meeting
    var aiservice: AIService
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Attendees
                VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("ATTENDEES (\(meeting.summary?.attendees.count ?? 0))")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            if let attendees = meeting.summary?.attendees, !attendees.isEmpty {
                                ForEach(attendees, id: \.self) { name in
                                    AttendeeBadge(name: name, color: attendeeColor(for: name))
                                }
                            } else {
                                Text("No attendees identified")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                if let summary = meeting.summary {
                    @Bindable var s = summary
                    
                    SectionCard(icon: "text.alignleft", title: "Overview") {
                        TextEditor(text: $s.overview)
                            .font(.body)
                            .lineSpacing(5)
                            .frame(minHeight: 80)
                            .scrollContentBackground(.hidden)
                    }
                    
                    SectionCard(icon: "checkmark.square", title: "Action Items") {
                        VStack(alignment: .leading, spacing: 16) {
                            if meeting.actionItems.isEmpty {
                                Text("No action items")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 4)
                            } else {
                                let grouped = Dictionary(grouping: meeting.actionItems) { item -> String in
                                    if let match = item.task.range(of: "^\\[(.*?)\\]", options: .regularExpression) {
                                        return String(item.task[match]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                                    }
                                    return "Unassigned"
                                }.sorted { $0.key < $1.key }
                                
                                ForEach(grouped, id: \.key) { group in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(group.key)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundColor(.secondary)
                                    
                                    ForEach(group.value) { item in
                                        @Bindable var bi = item
                                        HStack(alignment: .top, spacing: 10) {
                                            Toggle("", isOn: $bi.isCompleted)
                                                .toggleStyle(CheckboxStyle())
                                            
                                            // Strip the speaker prefix for editing if it exists
                                            let bindingTask = Binding(
                                                get: {
                                                    if let match = bi.task.range(of: "^\\[(.*?)\\]\\s*", options: .regularExpression) {
                                                        return String(bi.task[bi.task.index(match.upperBound, offsetBy: 0)...])
                                                    }
                                                    return bi.task
                                                },
                                                set: { newValue in
                                                    if let match = bi.task.range(of: "^\\[(.*?)\\]\\s*", options: .regularExpression) {
                                                        let prefix = String(bi.task[match])
                                                        bi.task = prefix + newValue
                                                    } else {
                                                        bi.task = newValue
                                                    }
                                                }
                                            )
                                            
                                            TextField("Task", text: bindingTask)
                                                .textFieldStyle(.plain)
                                                .foregroundColor(item.isCompleted ? .secondary : .primary)
                                                .strikethrough(item.isCompleted)
                                        }
                                    }
                                }
                            }
                            } // Close else
                            
                            Button(action: {
                                let newItem = ActionItem(task: "")
                                meeting.actionItems.append(newItem)
                                modelContext.insert(newItem)
                            }) {
                                Label("Add action item and press Enter", systemImage: "plus")
                                    .foregroundColor(.blue)
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                    }
                    
                    SectionCard(icon: "sparkles", title: "Insights") {
                        InsightsListView(insightsText: s.insights)
                    }
                    
                    SectionCard(icon: "list.bullet.indent", title: "Outline") {
                        InteractiveOutlineView(outlineText: $s.outline)
                    }
                    
                    SectionCard(icon: "checkmark.seal", title: "Key Decisions") {
                        InsightsListView(insightsText: s.keyDecisions)
                    }
                    
                    SectionCard(icon: "questionmark.bubble", title: "Open Questions") {
                        InsightsListView(insightsText: s.openQuestions)
                    }
                    
                } else {
                    if aiservice.isProcessing {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Generating Summary...")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 50)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 36))
                                .foregroundColor(.secondary)
                            Text("Summary will appear after recording or upload.")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 50)
                    }
                }
            }
            .padding(24)
            .padding(.bottom, 80)
        }
    }
    
    private func attendeeColor(for name: String) -> Color {
        let colors: [Color] = [.red, .blue, .green, .orange, .purple, .pink, .teal]
        let hash = abs(name.hashValue)
        return colors[hash % colors.count]
    }
}

// MARK: - Section Card
struct SectionCard: View {
    let icon: String
    let title: String
    let content: () -> AnyView
    
    init<Content: View>(icon: String, title: String, @ViewBuilder content: @escaping () -> Content) {
        self.icon = icon
        self.title = title
        self.content = { AnyView(content()) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.title3.weight(.semibold))
                Spacer()
            }
            
            content()
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }
}

struct AttendeeBadge: View {
    var name: String
    var color: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 20, height: 20)
                .overlay(
                    Text(String(name.prefix(1)).uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                )
            Text(name)
                .font(.subheadline)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .cornerRadius(16)
    }
}

struct CheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                .foregroundColor(configuration.isOn ? .blue : .secondary)
                .font(.body)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Transcript View
struct TranscriptView: View {
    @Bindable var meeting: Meeting
    @Environment(TranscriptionService.self) private var transcriptionService
    @Environment(WhisperTranscriptionService.self) private var whisperService
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if (transcriptionService.isTranscribing && transcriptionService.currentTranscribingMeetingId == meeting.id) ||
                   (whisperService.isTranscribing && whisperService.currentTranscribingMeetingId == meeting.id) {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(whisperService.statusMessage.isEmpty ? "Transcribing audio..." : whisperService.statusMessage)
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else if meeting.transcript.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text("No transcript yet. Record or upload audio.")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    let sortedSegments = meeting.transcript.sorted(by: { $0.timestamp < $1.timestamp })
                    ForEach(sortedSegments) { segment in
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Text(String((segment.speaker ?? "S").prefix(1)))
                                        .font(.caption.bold())
                                        .foregroundColor(.primary)
                                )
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(segment.speaker ?? "Speaker")
                                        .font(.subheadline.weight(.semibold))
                                    Text(formatTimestamp(segment.timestamp))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Text(segment.text)
                                    .font(.body)
                                    .lineSpacing(4)
                                    .textSelection(.enabled)
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 24)
                    }
                }
            }
            .padding(.vertical, 20)
            .padding(.bottom, 80)
        }
    }
    
    func formatTimestamp(_ ts: TimeInterval) -> String {
        let min = Int(ts) / 60
        let sec = Int(ts) % 60
        return String(format: "%02d:%02d", min, sec)
    }
}

// MARK: - Notes View
struct NotesView: View {
    @Bindable var meeting: Meeting
    @Environment(\.modelContext) private var modelContext
    @State private var noteText: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 15) {
                Group {
                    Image(systemName: "bold")
                    Image(systemName: "italic")
                }
                Divider().frame(height: 15)
                Group {
                    Image(systemName: "list.bullet")
                    Image(systemName: "list.number")
                    Image(systemName: "checklist")
                }
                Divider().frame(height: 15)
                Image(systemName: "link")
                
                Spacer()
                
                Button(action: {}) {
                    Label("AI Enhance", systemImage: "sparkles")
                        .foregroundColor(.blue)
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            TextEditor(text: $noteText)
                .font(.body)
                .lineSpacing(4)
                .padding(16)
                .scrollContentBackground(.hidden)
        }
    }
}

// MARK: - Insights List View

/// Renders AI-generated insights as a clean bullet list.
/// Automatically strips any **Label**: prefix patterns the AI might have added.
struct InsightsListView: View {
    let insightsText: String

    private var bullets: [String] {
        insightsText
            .components(separatedBy: .newlines)
            .compactMap { line -> String? in
                var text = line.trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { return nil }

                // Strip bullet markers: "- ", "• ", "* "
                if text.hasPrefix("- ") { text = String(text.dropFirst(2)) }
                else if text.hasPrefix("• ") { text = String(text.dropFirst(2)) }
                else if text.hasPrefix("* ") { text = String(text.dropFirst(2)) }
                guard !text.isEmpty else { return nil }

                // Strip leading **Label**: or **Label** - patterns
                // e.g. "**Actionable Insight**: The team..." → "The team..."
                if let regex = try? NSRegularExpression(pattern: #"^\*\*[^*]+\*\*\s*[:–\-]\s*"#),
                   let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                   let range = Range(match.range, in: text) {
                    text = String(text[range.upperBound...])
                }

                return text.isEmpty ? nil : text
            }
    }

    var body: some View {
        if insightsText.starts(with: "Generating") {
            Text(insightsText)
                .font(.body)
                .foregroundColor(.secondary)
                .padding(.vertical, 4)
        } else if bullets.isEmpty {
            Text("None")
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

