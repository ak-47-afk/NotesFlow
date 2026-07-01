import SwiftUI

struct CommandPaletteView: View {
    var meetings: [Meeting]
    @Binding var selectedMeeting: Meeting?
    @Environment(\.dismiss) var dismiss
    
    @State private var searchText = ""
    
    var filteredMeetings: [Meeting] {
        if searchText.isEmpty { return meetings }
        return meetings.filter { meeting in
            meeting.title.localizedCaseInsensitiveContains(searchText) ||
            meeting.transcript.contains(where: { $0.text.localizedCaseInsensitiveContains(searchText) }) ||
            meeting.actionItems.contains(where: { ($0.owner ?? "").localizedCaseInsensitiveContains(searchText) || $0.task.localizedCaseInsensitiveContains(searchText) })
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search meetings, transcripts, action items...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.title3)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            List(filteredMeetings) { meeting in
                Button(action: {
                    selectedMeeting = meeting
                    dismiss()
                }) {
                    VStack(alignment: .leading) {
                        Text(meeting.title).font(.headline)
                        if !searchText.isEmpty {
                            // Highlighting matching context could be added here
                            Text("Match found in contents")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            }
        }
        .frame(width: 500, height: 400)
        .background(Material.regularMaterial)
        .cornerRadius(12)
    }
}
