import SwiftUI

struct EmptyStateView: View {
    var hasMeetings: Bool = false
    var onRecord: () -> Void
    var onUpload: () -> Void
    
    var body: some View {
        VStack(spacing: 40) {
            
            HStack(spacing: 20) {
                FeatureCard(
                    icon: "doc.text",
                    title: "Audio Transcripts",
                    description: "Speaker-attributed,\nsearchable."
                )
                
                FeatureCard(
                    icon: "sparkles",
                    title: "AI Summaries",
                    description: "Overview, actions, insights."
                )
                
                FeatureCard(
                    icon: "message",
                    title: "Chat with notes",
                    description: "Ask questions\nacross meetings."
                )
            }
            .padding(.top, 40)
            
            VStack(spacing: 12) {
                if hasMeetings {
                    Text("Select a Meeting")
                        .font(.system(size: 28, weight: .bold))
                    
                    Text("Choose a meeting from the sidebar to view its transcript and summary,\nor record a new one.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .lineSpacing(4)
                } else {
                    Text("Welcome to NotesFlow")
                        .font(.system(size: 28, weight: .bold))
                    
                    Text("You don't have any meetings yet. Record your first meeting to get\na transcript, AI summary, and action items — all stored privately\non your device.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .lineSpacing(4)
                }
            }
            
            HStack(spacing: 20) {
                Button(action: onRecord) {
                    HStack {
                        Image(systemName: "mic")
                        Text(hasMeetings ? "Record New Meeting" : "Record Your First Meeting")
                    }
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                
                Button(action: onUpload) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Upload Audio")
                    }
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.1))
                    .foregroundColor(.primary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
}

struct FeatureCard: View {
    var icon: String
    var title: String
    var description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(width: 220, height: 160, alignment: .topLeading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }
}
