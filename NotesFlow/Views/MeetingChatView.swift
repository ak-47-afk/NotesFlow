import SwiftUI
import SwiftData

struct MeetingChatView: View {
    var meeting: Meeting
    var aiservice: AIService
    @Environment(\.modelContext) private var modelContext
    
    @Query private var allSessions: [ChatSession]
    @State private var session: ChatSession?
    
    @State private var chatQuery: String = ""
    @State private var isTyping = false
    
    let suggestedQuestions = [
        "What were the key takeaways?",
        "Are there any action items for me?",
        "Summarize this meeting."
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Meeting Chat")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            if let session = session {
                // Chat History
                ScrollView {
                    ScrollViewReader { proxy in
                        VStack(spacing: 16) {
                            ForEach(session.messages.sorted(by: { $0.timestamp < $1.timestamp })) { msg in
                                Text(msg.text)
                                    .padding(12)
                                    .background(msg.isUser ? Color.blue.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(8)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: msg.isUser ? .trailing : .leading)
                                    .padding(.horizontal)
                                    .id(msg.id)
                            }
                            
                            if isTyping {
                                HStack(spacing: 4) {
                                    Circle().frame(width: 6, height: 6).opacity(0.4)
                                    Circle().frame(width: 6, height: 6).opacity(0.6)
                                    Circle().frame(width: 6, height: 6).opacity(0.8)
                                }
                                .padding(12)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                                .id("typing")
                            }
                        }
                        .padding(.vertical)
                        .onChange(of: session.messages.count) {
                            if let last = session.messages.sorted(by: { $0.timestamp < $1.timestamp }).last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Suggested Questions
                if session.messages.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(suggestedQuestions, id: \.self) { question in
                            Button(action: {
                                chatQuery = question
                                sendMessage()
                            }) {
                                Text(question)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(20)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
                
                // Input Area
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.blue)
                    
                    TextField("Ask about this meeting...", text: $chatQuery)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            sendMessage()
                        }
                        .disabled(isTyping)
                    
                    Button(action: sendMessage) {
                        Image(systemName: "paperplane.fill")
                            .foregroundColor(chatQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(chatQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTyping)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor).cornerRadius(20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                .padding()
            } else {
                Spacer()
                ProgressView()
                Spacer()
            }
        }
        .frame(width: 300)
        .background(Color(NSColor.textBackgroundColor))
        .onAppear {
            setupSession()
        }
        .onChange(of: meeting.id) {
            setupSession()
        }
    }
    
    private func setupSession() {
        if let existing = allSessions.first(where: { $0.relatedMeetingIDs == [meeting.id] }) {
            self.session = existing
        } else {
            let newSession = ChatSession(title: meeting.title)
            newSession.relatedMeetingIDs = [meeting.id]
            modelContext.insert(newSession)
            self.session = newSession
        }
    }
    
    private func sendMessage() {
        let query = chatQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let session = session else { return }
        
        let userMsg = ChatMessage(text: query, isUser: true)
        userMsg.session = session
        modelContext.insert(userMsg)
        
        chatQuery = ""
        isTyping = true
        
        let context = buildContext()
        
        aiservice.chat(query: query, context: context) { reply in
            let botMsg = ChatMessage(text: reply, isUser: false)
            botMsg.session = session
            modelContext.insert(botMsg)
            isTyping = false
        }
    }
    
    private func buildContext() -> String {
        var context = ""
        context += "Meeting Title: \(meeting.title)\n"
        if let summary = meeting.summary {
            context += "Summary Overview: \(summary.overview)\n"
            context += "Action Items: \(meeting.actionItems.map { $0.task }.joined(separator: ", "))\n"
        }
        let transcriptText = meeting.transcript.map { "\($0.speaker ?? "Speaker"): \($0.text)" }.joined(separator: "\n")
        context += "Transcript:\n\(transcriptText)\n"
        return context
    }
}
