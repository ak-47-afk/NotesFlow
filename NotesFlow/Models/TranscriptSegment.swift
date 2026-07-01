import Foundation
import SwiftData

@Model
final class TranscriptSegment {
    var id: UUID
    var text: String
    var timestamp: TimeInterval
    var speaker: String?
    
    var meeting: Meeting?

    init(id: UUID = UUID(), text: String, timestamp: TimeInterval, speaker: String? = nil) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.speaker = speaker
    }
}
