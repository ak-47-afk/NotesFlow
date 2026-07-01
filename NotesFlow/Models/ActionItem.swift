import Foundation
import SwiftData

@Model
final class ActionItem {
    var id: UUID
    var task: String = ""
    var owner: String?
    var deadline: Date?
    var isCompleted: Bool
    
    var meeting: Meeting?

    init(id: UUID = UUID(), task: String, owner: String? = nil, deadline: Date? = nil, isCompleted: Bool = false) {
        self.id = id
        self.task = task
        self.owner = owner
        self.deadline = deadline
        self.isCompleted = isCompleted
    }
}
