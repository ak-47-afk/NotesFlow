import SwiftUI
import SwiftData
import AVFoundation

struct MainSplitView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meeting.date, order: .reverse) private var meetings: [Meeting]
    @Query(sort: \ChatSession.date, order: .reverse) private var chatSessions: [ChatSession]
    
    @Environment(AudioRecorderService.self) private var audioService
    @State private var showingSettingsOverlay = false
    
    @State private var selectedMeeting: Meeting?
    @State private var selectedSession: ChatSession?
    @State private var showingUploadModal = false
    @State private var sidebarSelection = "Meetings"
    @Environment(TranscriptionService.self) private var transcriptionService
    @Environment(AIService.self) private var aiService
    @Environment(WhisperTranscriptionService.self) private var whisperService
    
    var body: some View {
        ZStack {
            HStack(spacing: 0) {
            // MARK: - Sidebar
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 12) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    VStack(alignment: .leading) {
                        Text("NotesFlow")
                            .font(.headline)
                        Text("Local-first sync")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 20)
                .padding(.bottom, 10)
                
                // Buttons
                VStack(spacing: 10) {
                    Button(action: startNewMeeting) {
                        HStack {
                            Image(systemName: "plus")
                            Text("New Recording")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    
                    Button(action: { showingUploadModal = true }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Upload Audio")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.horizontal)
                
                // Meetings List
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(["Meetings", "Chats"], id: \.self) { tab in
                                Button(action: { sidebarSelection = tab }) {
                                    Text(tab)
                                        .font(.system(size: 13, weight: sidebarSelection == tab ? .medium : .regular))
                                        .foregroundColor(sidebarSelection == tab ? .primary : .secondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 4)
                                        .background(
                                            sidebarSelection == tab ?
                                            Color(NSColor.controlBackgroundColor) : Color.clear
                                        )
                                        .clipShape(Capsule())
                                        .shadow(color: sidebarSelection == tab ? Color.black.opacity(0.1) : .clear, radius: 2, y: 1)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(2)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Capsule())
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        
                        if sidebarSelection == "Meetings" {
                            ForEach(meetings) { meeting in
                                MeetingRowView(
                                    meeting: meeting,
                                    isSelected: selectedMeeting?.id == meeting.id
                                ) {
                                    selectedMeeting = meeting
                                } onDelete: {
                                    if selectedMeeting?.id == meeting.id { selectedMeeting = nil }
                                    modelContext.delete(meeting)
                                }
                            }
                        } else {
                            Button(action: startNewChat) {
                                HStack {
                                    Image(systemName: "plus.bubble")
                                    Text("New Chat")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                            
                            let activeSessions = chatSessions.filter { !$0.messages.isEmpty }
                            ForEach(activeSessions) { session in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(session.title)
                                            .font(.headline)
                                            .lineLimit(1)
                                        Text(session.date.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding()
                                .background(selectedSession?.id == session.id ? Color.accentColor.opacity(0.1) : Color.clear)
                                .cornerRadius(8)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedSession = session
                                }
                                .contextMenu {
                                    Button("Delete", role: .destructive) {
                                        if selectedSession?.id == session.id { selectedSession = nil }
                                        modelContext.delete(session)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Spacer(minLength: 0)
                
                // Footer Settings
                VStack(alignment: .leading, spacing: 15) {
                    Divider()
                    Button(action: {
                        showingSettingsOverlay = true
                    }) {
                        Label("Settings", systemImage: "gearshape")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(",", modifiers: .command)
                }
                .padding()
            }
            .frame(width: 260)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // MARK: - Detail Area
            VStack(spacing: 0) {
                // Content
                if sidebarSelection == "Meetings" {
                    if let meeting = selectedMeeting {
                        MeetingDetailView(meeting: meeting)
                    } else {
                        EmptyStateView(hasMeetings: !meetings.isEmpty, onRecord: startNewMeeting, onUpload: { showingUploadModal = true })
                    }
                } else {
                    if let session = selectedSession {
                        GlobalChatView(session: session, allMeetings: meetings, aiservice: aiService)
                    } else {
                        VStack {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("Select a chat or start a new one.")
                                .font(.title3)
                                .foregroundColor(.secondary)
                                .padding(.top)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.textBackgroundColor))
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StartRecordingAction"))) { _ in
            startNewMeeting()
        }
            if showingSettingsOverlay {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showingSettingsOverlay = false
                    }
                
                SettingsView(isPresented: $showingSettingsOverlay)
            }
        }
        .sheet(isPresented: $showingUploadModal) {
            UploadModalView { url in
                handleUploadedFile(url: url)
            }
        }
    }
    
    private func handleUploadedFile(url: URL) {
        let hasAccess = url.startAccessingSecurityScopedResource()
        
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDataDir = appSupport.appendingPathComponent("NotesFlow", isDirectory: true)
        
        do {
            if !fileManager.fileExists(atPath: appDataDir.path) {
                try fileManager.createDirectory(at: appDataDir, withIntermediateDirectories: true)
            }
            
            let destinationURL = appDataDir.appendingPathComponent(url.lastPathComponent)
            
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            
            try fileManager.copyItem(at: url, to: destinationURL)
            
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
            
            let newMeeting = Meeting()
            newMeeting.audioFilePath = destinationURL.path
            newMeeting.source = "Uploaded Audio"
            
            // Extract creation date from original file
            if let resourceValues = try? url.resourceValues(forKeys: [.creationDateKey]),
               let creationDate = resourceValues.creationDate {
                newMeeting.date = creationDate
            } else if let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                      let creationDate = attributes[.creationDate] as? Date {
                newMeeting.date = creationDate
            }
            
            // Calculate exact duration using AVURLAsset
            let asset = AVURLAsset(url: destinationURL)
            let durationInSeconds = CMTimeGetSeconds(asset.duration)
            if !durationInSeconds.isNaN {
                let min = Int(durationInSeconds) / 60
                let sec = Int(durationInSeconds) % 60
                newMeeting.duration = String(format: "%02d:%02d", min, sec)
            }
            
            selectedMeeting = newMeeting
            modelContext.insert(newMeeting)
            
            transcriptionService.isTranscribing = true
            transcriptionService.currentTranscribingMeetingId = newMeeting.id
            whisperService.currentTranscribingMeetingId = newMeeting.id
            aiService.isProcessing = true
            
            Task {
                do {
                    let segments = try await whisperService.transcribe(audioURL: destinationURL)
                    await MainActor.run {
                        transcriptionService.isTranscribing = false
                        transcriptionService.currentTranscribingMeetingId = nil
                        whisperService.currentTranscribingMeetingId = nil
                        newMeeting.transcript = segments
                        for segment in segments {
                            segment.meeting = newMeeting
                            modelContext.insert(segment)
                        }
                        
                        let transcriptText = segments.map { $0.text }.joined(separator: " ")
                        if !transcriptText.isEmpty {
                            if let existingSummary = newMeeting.summary {
                                existingSummary.overview = "Generating overview..."
                                existingSummary.keyDecisions = "Generating key decisions..."
                                existingSummary.openQuestions = "Generating open questions..."
                                existingSummary.insights = "Generating insights..."
                                existingSummary.outline = "Generating outline..."
                            } else {
                                let tempSummary = Summary(overview: "Generating overview...", insights: "Generating insights...", outline: "Generating outline...", keyDecisions: "Generating key decisions...", openQuestions: "Generating open questions...", attendees: [], templateName: "Default Built-In")
                                newMeeting.summary = tempSummary
                                modelContext.insert(tempSummary)
                            }
                            aiService.generateSummary(transcript: transcriptText, using: nil, onFastResult: { fastResult in
                                newMeeting.title = fastResult.title != "New Meeting" ? fastResult.title : newMeeting.title
                                
                                if let existingSummary = newMeeting.summary {
                                    existingSummary.overview = fastResult.overview
                                    existingSummary.keyDecisions = fastResult.keyDecisions
                                    existingSummary.openQuestions = fastResult.openQuestions
                                    existingSummary.attendees = fastResult.attendees
                                    existingSummary.templateName = "Default Built-In"
                                }
                                
                                // Delete old action items
                                newMeeting.actionItems.forEach { modelContext.delete($0) }
                                newMeeting.actionItems.removeAll()
                                
                                // Insert new action items
                                for item in fastResult.actionItems {
                                    let actionItem = ActionItem(task: "[\(item.speaker)] \(item.task)", isCompleted: false)
                                    newMeeting.actionItems.append(actionItem)
                                    modelContext.insert(actionItem)
                                }
                            }, onOutlineStream: { partialOutline in
                                newMeeting.summary?.outline = partialOutline
                            }, onInsightsComplete: { fullInsights in
                                newMeeting.summary?.insights = fullInsights
                            }, onComplete: { success in
                                aiService.isProcessing = false
                                if success {
                                    NotificationManager.shared.sendNotification(title: "Meeting Processed", body: "Summary generated for '\(newMeeting.title)'.")
                                }
                            }, onError: { errorMsg in
                                AppLogger.error("Summary generation error: \(errorMsg)")
                                if newMeeting.summary?.insights == "Generating insights..." {
                                    newMeeting.summary?.insights = "Error: \(errorMsg)"
                                }
                                if newMeeting.summary?.outline == "Generating outline..." {
                                    newMeeting.summary?.outline = ""
                                }
                                if newMeeting.summary?.keyDecisions == "Generating key decisions..." {
                                    newMeeting.summary?.keyDecisions = ""
                                }
                                if newMeeting.summary?.openQuestions == "Generating open questions..." {
                                    newMeeting.summary?.openQuestions = ""
                                }
                                if newMeeting.summary?.overview == "Generating overview..." {
                                    newMeeting.summary?.overview = ""
                                }
                                aiService.isProcessing = false
                            })
                        } else {
                            aiService.isProcessing = false
                        }
                    }
                } catch {
                    print("WhisperKit transcription failed: \(error)")
                    await MainActor.run {
                        transcriptionService.isTranscribing = false
                        transcriptionService.currentTranscribingMeetingId = nil
                        whisperService.currentTranscribingMeetingId = nil
                        aiService.isProcessing = false
                    }
                }
            }
        } catch {
            print("Failed to copy file to sandbox: \(error)")
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }
    
    private func startNewMeeting() {
        let activeMeetings = MeetingDetectorService.shared.getActiveMeetings()
        let sourceName = activeMeetings.first?.name ?? "In Person" // Default if none detected
        
        let newMeeting = Meeting(title: "New Meeting", source: sourceName)
        modelContext.insert(newMeeting)
        selectedMeeting = newMeeting
        
        // Reset chunked transcription state
        whisperService.resetTranscriptionState()
        
        // Wire up background chunk transcription
        audioService.onChunkReady = { [weak whisperService] chunk, duration, isSilence in
            Task {
                await whisperService?.transcribeChunk(audioArray: chunk, duration: duration, isSilence: isSilence)
            }
        }
        
        audioService.onRecordingFinished = { [weak newMeeting, weak whisperService, weak transcriptionService, weak aiService, audioService, modelContext] url in
            guard let meeting = newMeeting else { return }
            
            // Set the audio path now that it's finished
            meeting.audioFilePath = url.path
            meeting.duration = audioService.recordingDuration
            
            transcriptionService?.stopLiveTranscription()
            
            transcriptionService?.isTranscribing = true
            transcriptionService?.currentTranscribingMeetingId = meeting.id
            whisperService?.currentTranscribingMeetingId = meeting.id
            aiService?.isProcessing = true
            
            Task {
                do {
                    let segments = try await whisperService?.finishLiveTranscription(audioURL: url) ?? []
                    await MainActor.run {
                        transcriptionService?.isTranscribing = false
                        transcriptionService?.currentTranscribingMeetingId = nil
                        whisperService?.currentTranscribingMeetingId = nil
                        meeting.transcript.forEach { modelContext.delete($0) }
                        meeting.transcript = segments
                        for segment in segments {
                            segment.meeting = meeting
                            modelContext.insert(segment)
                        }
                        
                        let transcriptText = segments.map { $0.text }.joined(separator: " ")
                        if !transcriptText.isEmpty {
                            if let existingSummary = meeting.summary {
                                existingSummary.overview = "Generating overview..."
                                existingSummary.keyDecisions = "Generating key decisions..."
                                existingSummary.openQuestions = "Generating open questions..."
                                existingSummary.insights = "Generating insights..."
                                existingSummary.outline = "Generating outline..."
                            } else {
                                let tempSummary = Summary(overview: "Generating overview...", insights: "Generating insights...", outline: "Generating outline...", keyDecisions: "Generating key decisions...", openQuestions: "Generating open questions...", attendees: [], templateName: "Default Built-In")
                                meeting.summary = tempSummary
                                modelContext.insert(tempSummary)
                            }
                            aiService?.generateSummary(transcript: transcriptText, using: nil, onFastResult: { fastResult in
                                meeting.title = fastResult.title != "New Meeting" ? fastResult.title : meeting.title
                                
                                if let existingSummary = meeting.summary {
                                    existingSummary.overview = fastResult.overview
                                    existingSummary.keyDecisions = fastResult.keyDecisions
                                    existingSummary.openQuestions = fastResult.openQuestions
                                    existingSummary.attendees = fastResult.attendees
                                    existingSummary.templateName = "Default Built-In"
                                    // Empty insights and outline to show generation progress
                                    existingSummary.insights = "Generating insights..."
                                    existingSummary.outline = "Generating outline..."
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
                                aiService?.isProcessing = false
                                if success {
                                    NotificationManager.shared.sendNotification(title: "Meeting Processed", body: "Summary generated for '\(meeting.title)'.")
                                }
                            }, onError: { errorMsg in
                                AppLogger.error("Summary generation error: \(errorMsg)")
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
                                aiService?.isProcessing = false
                            })
                        } else {
                            aiService?.isProcessing = false
                        }
                    }
                } catch {
                    print("WhisperKit transcription failed: \(error)")
                    await MainActor.run {
                        transcriptionService?.isTranscribing = false
                        transcriptionService?.currentTranscribingMeetingId = nil
                        whisperService?.currentTranscribingMeetingId = nil
                        aiService?.isProcessing = false
                    }
                }
            }
        }
        
        audioService.startRecording()
        
        let liveSegment = TranscriptSegment(text: "", timestamp: Date().timeIntervalSince1970, speaker: "Speaker")
        liveSegment.meeting = newMeeting
        modelContext.insert(liveSegment)
        newMeeting.transcript.append(liveSegment)
        
        let tService = transcriptionService
        audioService.onRawMicBuffer = { buffer in
            tService.appendBuffer(buffer)
        }
        DispatchQueue.global(qos: .userInitiated).async {
            tService.startLiveTranscription { text, _ in
                DispatchQueue.main.async {
                    liveSegment.text = text
                }
            }
        }
    }
    
    private func startNewChat() {
        let newSession = ChatSession()
        selectedSession = newSession
        modelContext.insert(newSession)
    }
}

struct MeetingRowView: View {
    @Bindable var meeting: Meeting
    var isSelected: Bool = false
    var action: () -> Void
    var onDelete: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(meeting.title)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                }
                Text("\(meeting.date.formatted(date: .abbreviated, time: .omitted)) · \(meeting.duration)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.blue.opacity(0.15) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete Meeting", systemImage: "trash")
            }
        }
    }
}
