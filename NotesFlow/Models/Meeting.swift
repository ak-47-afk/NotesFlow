import Foundation
import SwiftData

@Model
final class Meeting {
    var id: UUID
    var title: String
    var date: Date
    var duration: String
    var audioFilePath: String?
    
    @Relationship(deleteRule: .cascade, inverse: \TranscriptSegment.meeting)
    var transcript: [TranscriptSegment] = []
    
    @Relationship(deleteRule: .cascade, inverse: \Summary.meeting)
    var summary: Summary?
    
    @Relationship(deleteRule: .cascade, inverse: \ActionItem.meeting)
    var actionItems: [ActionItem] = []
    
    @Relationship(deleteRule: .cascade, inverse: \Note.meeting)
    var notes: [Note] = []
    
    var source: String = "In Person"
    
    @Transient
    var audioURL: URL? {
        guard let path = audioFilePath else { return nil }
        
        let filename = URL(fileURLWithPath: path).lastPathComponent
        let docPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // 1. Check the new dedicated NotesFlow/Recordings directory
        let newRecordingsDir = docPath.appendingPathComponent("NotesFlow").appendingPathComponent("Recordings")
        let dedicatedUrl = newRecordingsDir.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: dedicatedUrl.path) {
            return dedicatedUrl
        }
        
        // 2. Check the legacy root Documents directory
        let rootDocUrl = docPath.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: rootDocUrl.path) {
            return rootDocUrl
        }
        
        // 3. Check legacy Application Support directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDataDir = appSupport.appendingPathComponent("NotesFlow", isDirectory: true)
        let legacyAppSupportUrl = appDataDir.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: legacyAppSupportUrl.path) {
            return legacyAppSupportUrl
        }
        
        // Fallback to exactly what is stored (e.g. absolute path if it was used)
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        
        return rootDocUrl
    }

    init(id: UUID = UUID(), title: String = "New Meeting", date: Date = Date(), duration: String = "00:00", audioFilePath: String? = nil, source: String = "In Person") {
        self.id = id
        self.title = title
        self.date = date
        self.duration = duration
        self.audioFilePath = audioFilePath
        self.source = source
    }
}

@Model
final class ChatSession {
    var id: UUID
    var title: String
    var date: Date
    
    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.session)
    var messages: [ChatMessage] = []
    
    var relatedMeetingIDs: [UUID] = []
    
    init(id: UUID = UUID(), title: String = "New Chat", date: Date = Date()) {
        self.id = id
        self.title = title
        self.date = date
    }
}

@Model
final class ChatMessage {
    var id: UUID
    var text: String
    var isUser: Bool
    var timestamp: Date
    
    var session: ChatSession?
    
    // We keep a soft reference to a meeting just in case we want to attach it later
    var meetingId: UUID?
    
    init(id: UUID = UUID(), text: String, isUser: Bool, timestamp: Date = Date(), meetingId: UUID? = nil) {
        self.id = id
        self.text = text
        self.isUser = isUser
        self.timestamp = timestamp
        self.meetingId = meetingId
    }
}

@Model
final class SummaryTemplate {
    var id: UUID
    var title: String
    var formatDescription: String
    var sections: String = "Overview, Insights, Outline, Action Items"
    
    init(id: UUID = UUID(), title: String, formatDescription: String, sections: String = "Overview, Insights, Outline, Action Items") {
        self.id = id
        self.title = title
        self.formatDescription = formatDescription
        self.sections = sections
    }
}
