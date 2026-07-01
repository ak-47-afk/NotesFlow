import Foundation
import SwiftData

@Model
final class Note {
    var id: UUID
    var text: String
    var createdAt: Date
    
    var meeting: Meeting?

    init(id: UUID = UUID(), text: String = "", createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}
