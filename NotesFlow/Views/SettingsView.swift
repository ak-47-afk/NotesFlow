import SwiftUI
import SwiftData

struct SettingsView: View {
    @Binding var isPresented: Bool
    
    @Environment(\.modelContext) private var modelContext
    @Query private var templates: [SummaryTemplate]
    
    @AppStorage("appAppearance") private var appAppearance: String = "Light"
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = true
    
    @AppStorage("geminiAPIKey") private var apiKey: String = ""
    @AppStorage("geminiModel") private var geminiModel: String = "gemini-3.5-flash"
    @AppStorage("speakerDiarization") private var speakerDiarization: Bool = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true
    @State private var apiKeySaveStatus: String = ""
    
    @State private var editingTemplate: SummaryTemplate? = nil
    @State private var showingTemplateEditor = false
    @StateObject private var permissions = PermissionsHelper()
    
    @Environment(WhisperTranscriptionService.self) private var whisperService
    
    enum FocusField {
        case dummy
        case apiKey
    }
    @FocusState private var focusedField: FocusField?
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom Header
            HStack {
                Text("Preferences")
                    .font(.headline)
                Spacer()
                Button(action: {
                    isPresented = false
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    TextField("", text: .constant(""))
                        .frame(width: 0, height: 0)
                        .focused($focusedField, equals: .dummy)
                        .opacity(0)
                        .accessibilityHidden(true)
                    
                    // GENERAL
                    VStack(alignment: .leading, spacing: 15) {
                        SettingsHeader(icon: "slider.horizontal.3", title: "General", subtitle: "App-wide preferences.")
                        Divider()
                        
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Theme").font(.body).bold()
                                Text("Light, Dark, or System.").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Picker("", selection: $appAppearance) {
                                Text("Light").tag("Light")
                                Text("Dark").tag("Dark")
                                Text("System").tag("System")
                            }
                            .pickerStyle(.menu)
                            .frame(width: 120)
                        }
                        
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Launch at login").font(.body).bold()
                                Text("Open NotesFlow when you sign in.").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $launchAtLogin).toggleStyle(.switch)
                        }
                    }
                    
                    // AI & API
                    VStack(alignment: .leading, spacing: 15) {
                        SettingsHeader(icon: "sparkles", title: "AI & API", subtitle: "Manage your API keys and models.")
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Google Gemini Model").font(.body).bold()
                            Text("Select which model to use for summaries.").font(.caption).foregroundColor(.secondary)
                            
                            Picker("", selection: $geminiModel) {
                                Text("Gemini 3.5 Flash").tag("gemini-3.5-flash")
                                Text("Gemini 3.5 Pro (High)").tag("gemini-3.5-pro")
                            }
                            .pickerStyle(.segmented)
                            .padding(.top, 5)
                            .padding(.bottom, 15)
                            
                            Text("Google Gemini API Key").font(.body).bold()
                            Text("Required for summarization. Get one at aistudio.google.com").font(.caption).foregroundColor(.secondary)
                            
                            HStack {
                                SecureField("Paste your API key here...", text: $apiKey)
                                    .textFieldStyle(.roundedBorder)
                                    .focused($focusedField, equals: .apiKey)
                                Button("Save") {
                                    KeychainHelper.standard.saveApiKey(apiKey)
                                    apiKeySaveStatus = "✓ Saved"
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        apiKeySaveStatus = ""
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .padding(.top, 5)
                            
                            if !apiKeySaveStatus.isEmpty {
                                Text(apiKeySaveStatus)
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    
                    // TRANSCRIPTION
                    VStack(alignment: .leading, spacing: 15) {
                        SettingsHeader(icon: "waveform", title: "Transcription", subtitle: "Local audio processing via WhisperKit.")
                        Divider()
                        
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Whisper Model").font(.body).bold()
                                Text("Select local transcription model size.").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Picker("", selection: Bindable(whisperService).selectedModel) {
                                ForEach(WhisperTranscriptionService.availableModels, id: \.id) { model in
                                    Text("\(model.name) (\(model.size))").tag(model.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 200)
                            .onChange(of: whisperService.selectedModel) { _, _ in
                                whisperService.resetModels()
                            }
                        }
                        
                        if whisperService.isDownloadingModel {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(whisperService.statusMessage)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                ProgressView()
                                    .controlSize(.small)
                            }
                            .padding(.top, 4)
                        } else if whisperService.isModelLoaded {
                            Text("✓ Model downloaded and ready")
                                .font(.caption)
                                .foregroundColor(.green)
                                .padding(.top, 4)
                        }
                        
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Speaker Diarization").font(.body).bold()
                                Text("Identify and label different speakers (SpeakerKit).").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Bindable(whisperService).diarizationEnabled).toggleStyle(.switch)
                        }
                    }
                    
                    // SUMMARY TEMPLATES
                    VStack(alignment: .leading, spacing: 15) {
                        SettingsHeader(icon: "doc.text", title: "Summary Templates", subtitle: "Reusable AI-driven meeting summary formats.")
                        Divider()
                        
                        VStack(spacing: 0) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Default Template").font(.body).bold()
                                    Text("Generates Title, Overview, Insights, Outline, and Attendees.").font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("Built-in").font(.caption).foregroundColor(.secondary).padding(.trailing, 8)
                                Button("View") {
                                    editingTemplate = SummaryTemplate(title: "Default Template", formatDescription: """
You are an expert Executive Meeting Assistant responsible for converting meeting transcripts into accurate, structured meeting notes.

Your primary goal is to produce notes that are factually correct, concise, complete, and immediately useful for participants.

## General Rules
- Base your output ONLY on information explicitly present in the transcript.
- Never invent attendees, decisions, action items, dates, owners, or conclusions.
- If information cannot be determined from the transcript, return null or an empty array instead of guessing.
- Ignore filler words, repeated phrases, greetings, interruptions, false starts, and casual conversation unless they affect the meaning of the discussion.
- Preserve all technical terminology, APIs, product names, code names, company names, metrics, and abbreviations exactly as spoken.
- Translate any Hindi or Hinglish into natural, professional English while preserving the original meaning.
- Always produce the output in English.
- Do not include markdown, explanations, or commentary outside the JSON response.
- Return ONLY valid JSON matching the required schema.

----------------------------
MEETING SUMMARY REQUIREMENTS
----------------------------

### 1. Meeting Title
Generate a concise and descriptive title.
Requirements:
- 3–7 words
- Clearly describe the main purpose of the meeting
- Avoid generic titles such as: Weekly Sync, Team Meeting, Discussion, Catch Up
Good examples: Milestone Billing Design Review, AI Meeting Notes Architecture, Revenue Recognition Planning

### 2. Overview
Write a concise executive summary.
Requirements:
- 3–5 sentences
- Explain: why the meeting happened, major discussion topics, important outcomes, next steps
- Do not include bullet points.

### 3. Key Insights
Extract strategic observations.
Include: important themes, recurring concerns, customer feedback, technical risks, opportunities, trade-offs discussed
Requirements:
- 3–8 items
- Do NOT repeat action items or decisions.

### 4. Detailed Outline
Create a structured outline of the discussion.
Requirements:
- Organize the meeting into logical sections with meaningful section titles.
- Group related discussions together using concise bullet points.
- Include: important technical discussions, numbers and metrics, architecture decisions, customer concerns, alternatives that were considered, rationale behind major discussions
- Mention speaker names only when doing so improves clarity.
- Avoid repeating the same information across multiple sections.
- Do NOT invent sections simply to increase length. Prefer quality over quantity.

### 5. Key Decisions
Extract every decision that was actually made. A decision is something that changes future work.
Include: approved approaches, selected options, rejected alternatives, finalized timelines, architecture choices, agreed implementation plans
Do NOT include: suggestions, brainstorming, opinions, possibilities, unresolved discussions
Each decision should be one complete sentence.

### 6. Open Questions
Extract unresolved questions.
Include: blockers, pending decisions, unanswered questions, items requiring follow-up
Do NOT include questions that were answered later in the meeting.

### 7. Attendees
Return every unique meeting participant.
Requirements:
- Include only actual meeting participants.
- If real names are not found, use their speaker labels (e.g., Speaker 0, Speaker 1, etc.).
- Exclude: customers mentioned during discussion, competitors, products, APIs, companies, people referenced only as examples

### 8. Action Items
Extract every actionable commitment.
Each action item should contain: task, owner, dueDate, priority
Rules:
Task: Must begin with a verb. Should describe one specific action. Do not merge multiple actions into one item.
Owner: Use the responsible person's name if clearly stated. Otherwise use null.
Due Date: Use the mentioned date or timeframe. Otherwise use null.
Priority: Choose one of HIGH, MEDIUM, LOW. Use HIGH only if the transcript clearly indicates urgency or a blocker.
Ignore: ideas, suggestions, brainstorming, hypothetical work, discussions without commitment
""", sections: "Overview, Action Items, Insights, Outline, Attendees")
                                    showingTemplateEditor = true
                                }
                                .padding(.trailing, 16)
                            }
                            .padding()
                            
                            Divider()
                            
                            ForEach(templates) { template in
                                TemplateRow(template: template, onEdit: {
                                    editingTemplate = template
                                    showingTemplateEditor = true
                                }, onDelete: {
                                    modelContext.delete(template)
                                })
                                Divider()
                            }
                            
                            HStack {
                                Button(action: {
                                    editingTemplate = nil
                                    showingTemplateEditor = true
                                }) {
                                    Label("Create template", systemImage: "plus")
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)
                                Spacer()
                            }
                            .padding()
                        }
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                    }
                    
                    // NOTIFICATIONS
                    VStack(alignment: .leading, spacing: 15) {
                        SettingsHeader(icon: "bell", title: "Notifications", subtitle: "Choose what to be alerted about.")
                        Divider()
                        
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Meeting summary ready").font(.body).bold()
                                Text("Notify when a summary finishes processing.").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $notificationsEnabled).toggleStyle(.switch)
                        }
                        
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Auto Detect Meetings").font(.body).bold()
                                Text("Notify when Zoom, Teams, or Meet is opened.").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { UserDefaults.standard.object(forKey: "autoDetectMeetings") as? Bool ?? true },
                                set: { newValue in
                                    UserDefaults.standard.set(newValue, forKey: "autoDetectMeetings")
                                    if newValue {
                                        MeetingDetectorService.shared.startMonitoring()
                                    } else {
                                        MeetingDetectorService.shared.stopMonitoring()
                                    }
                                }
                            )).toggleStyle(.switch)
                        }
                    }
                    
                    // PERMISSIONS
                    VStack(alignment: .leading, spacing: 15) {
                        SettingsHeader(icon: "shield", title: "Permissions", subtitle: "Manage system access required by NotesFlow.")
                        Divider()
                        
                        // Accessibility
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Accessibility").font(.body).bold()
                                Text("Required for native meeting detection if Screen Recording is denied.").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            if permissions.accessibilityGranted {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                                Button("Reset") {
                                    permissions.resetAccessibility()
                                }.buttonStyle(.bordered)
                            } else {
                                Button("Grant Access") {
                                    permissions.openAccessibilitySettings()
                                }.buttonStyle(.borderedProminent)
                            }
                        }
                        
                        // Screen Recording
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Screen & System Audio Recording").font(.body).bold()
                                Text("Required to automatically detect meetings from window titles.").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            if permissions.screenRecordingGranted {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                                Button("Reset") {
                                    permissions.resetScreenRecording()
                                }.buttonStyle(.bordered)
                            } else {
                                Button("Grant Access") {
                                    permissions.requestScreenRecording()
                                }.buttonStyle(.borderedProminent)
                            }
                        }
                        
                        // Microphone
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Microphone").font(.body).bold()
                                Text("Required to record audio for transcription.").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            if permissions.microphoneGranted {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                                Button("Reset") {
                                    permissions.resetMicrophone()
                                }.buttonStyle(.bordered)
                            } else {
                                Button("Grant Access") {
                                    permissions.requestMicrophone()
                                }.buttonStyle(.borderedProminent)
                            }
                        }
                        
                        // Notifications
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Notifications").font(.body).bold()
                                Text("Required to alert you when a meeting is detected.").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            if permissions.notificationsGranted {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            } else {
                                Button("Grant Access") {
                                    permissions.requestNotifications()
                                }.buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    
                }
                .padding(20)
            }
        }
        .frame(width: 550, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .shadow(radius: 20)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in
            permissions.checkPermissions()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = .dummy
            }
        }
        .sheet(isPresented: $showingTemplateEditor) {
            TemplateEditorView(template: $editingTemplate)
        }
    }
}

struct SettingsHeader: View {
    var icon: String
    var title: String
    var subtitle: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.primary)
                .frame(width: 36, height: 36)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3)
                    .bold()
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct TemplateRow: View {
    var template: SummaryTemplate
    var onEdit: () -> Void
    var onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(template.title).font(.body).bold()
                Text(template.formatDescription).font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            Button("Edit", action: onEdit)
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
        }
        .padding()
    }
}

struct TemplateSectionSelection: Identifiable, Hashable {
    var id = UUID()
    var name: String
}

struct TemplateEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss
    
    @Binding var template: SummaryTemplate?
    var isReadOnly: Bool {
        template?.title == "Default Template"
    }
    
    @State private var title: String = ""
    @State private var consolidatedPrompt: String = ""
    @State private var sections: [TemplateSectionSelection] = [
        TemplateSectionSelection(name: "Overview"),
        TemplateSectionSelection(name: "Action Items")
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(template == nil ? "Add template" : "Edit template")
                    .font(.title2.weight(.bold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Template Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Template name")
                            .font(.headline)
                        TextField("New Template", text: $title)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                            .disabled(isReadOnly)
                    }
                    
                    // Sections
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sections")
                            .font(.headline)
                        
                        ForEach($sections) { $section in
                            HStack {
                                TextField("Section name", text: $section.name)
                                    .textFieldStyle(.plain)
                                    .font(.body)
                                    .disabled(isReadOnly)
                                Spacer()
                                    if !isReadOnly {
                                        Button(action: {
                                            sections.removeAll(where: { $0.id == section.id })
                                        }) {
                                            Image(systemName: "trash")
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                            }
                            .padding(12)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                        }
                        
                        if !isReadOnly {
                            Button(action: {
                                sections.append(TemplateSectionSelection(name: "New section"))
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                    Text("Add section")
                                }
                                .font(.body.weight(.semibold))
                                .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                    }
                    
                    // Consolidated Prompt
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Consolidated AI Prompt")
                            .font(.headline)
                        Text("Provide custom instructions for the AI on how to format and generate the summary.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextEditor(text: $consolidatedPrompt)
                            .font(.body)
                            .padding(8)
                            .frame(minHeight: 120)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                            .disabled(isReadOnly)
                    }
                }
                .padding(20)
            }
            
            Divider()
            
            // Footer
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                
                if !isReadOnly {
                    Button("Save template") {
                        let activeSections = sections.map { $0.name }.joined(separator: ", ")
                        
                        if let existing = template {
                            existing.title = title
                            existing.sections = activeSections
                            existing.formatDescription = consolidatedPrompt
                        } else {
                            let newTemplate = SummaryTemplate(title: title.isEmpty ? "New Template" : title, formatDescription: consolidatedPrompt, sections: activeSections)
                            modelContext.insert(newTemplate)
                        }
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
            }
            .padding(20)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 500, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .onChange(of: template, initial: true) { _, t in
            if let t = t {
                title = t.title
                consolidatedPrompt = t.formatDescription
                
                let savedSections = t.sections.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                
                if !savedSections.isEmpty {
                    sections = savedSections.map { TemplateSectionSelection(name: $0) }
                }
            } else {
                title = ""
                consolidatedPrompt = ""
                sections = [
                    TemplateSectionSelection(name: "Overview"),
                    TemplateSectionSelection(name: "Action Items")
                ]
            }
        }
    }
}
