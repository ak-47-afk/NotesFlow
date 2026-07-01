import SwiftUI
import SwiftData

struct GlobalChatView: View {
    @Bindable var session: ChatSession
    var allMeetings: [Meeting]
    var aiservice: AIService
    @Environment(\.modelContext) private var modelContext
    
    @State private var chatQuery: String = ""
    @State private var isTyping = false
    
    let suggestedQuestions = [
        "What decisions were made recently?",
        "Was I mentioned in any recent meeting?",
        "Summarize all open action items."
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(session.title)
                    .font(.title2.weight(.semibold))
                Spacer()
                
                Menu {
                    Button(action: {
                        session.relatedMeetingIDs = []
                    }) {
                        HStack {
                            Text("All Meetings")
                            if session.relatedMeetingIDs.isEmpty {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    Divider()
                    ForEach(allMeetings) { m in
                        Button(action: {
                            if session.relatedMeetingIDs.contains(m.id) {
                                session.relatedMeetingIDs.removeAll { $0 == m.id }
                            } else {
                                session.relatedMeetingIDs.append(m.id)
                            }
                        }) {
                            HStack {
                                Text(m.title)
                                if session.relatedMeetingIDs.contains(m.id) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(session.relatedMeetingIDs.isEmpty ? "Context: All Meetings" : "Context: \(session.relatedMeetingIDs.count) Selected")
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
                .frame(width: 180)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
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
                    .foregroundColor(.secondary)
                
                TextField("Ask anything about your meetings...", text: $chatQuery)
                    .textFieldStyle(.plain)
                    .padding(.leading, 4)
                    .onSubmit(sendMessage)
                
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.white)
                        .padding(8)
                        .background(chatQuery.isEmpty ? Color.gray.opacity(0.3) : Color.blue)
                        .clipShape(Circle())
                }
                .disabled(chatQuery.isEmpty)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
    
    private func sendMessage() {
        guard !chatQuery.isEmpty else { return }
        let query = chatQuery
        chatQuery = ""
        
        let userMessage = ChatMessage(text: query, isUser: true)
        userMessage.session = session
        modelContext.insert(userMessage)
        session.messages.append(userMessage)
        
        // Rename session based on first message if it's "New Chat"
        if session.title == "New Chat" && session.messages.count == 1 {
            session.title = String(query.prefix(40)) + (query.count > 40 ? "..." : "")
        }
        
        isTyping = true
        
        // Compile context from selected meetings or all recent meetings
        let targetMeetings: [Meeting]
        if session.relatedMeetingIDs.isEmpty {
            targetMeetings = Array(allMeetings.sorted(by: { $0.date > $1.date }).prefix(5))
        } else {
            targetMeetings = allMeetings.filter { session.relatedMeetingIDs.contains($0.id) }
        }
        
        var contextString = ""
        for m in targetMeetings {
            contextString += "Meeting '\(m.title)' on \(m.date):\n"
            if let sum = m.summary {
                contextString += "Summary: \(sum.overview)\n"
            }
            let transcript = m.transcript.map { $0.text }.joined(separator: " ")
            if !transcript.isEmpty {
                contextString += "Transcript excerpt: \(String(transcript.prefix(1000)))\n"
            }
            contextString += "\n"
        }
        
        aiservice.chat(query: query, context: contextString) { response in
            isTyping = false
            let aiMessage = ChatMessage(text: response, isUser: false)
            aiMessage.session = session
            modelContext.insert(aiMessage)
            session.messages.append(aiMessage)
        }
    }
}
