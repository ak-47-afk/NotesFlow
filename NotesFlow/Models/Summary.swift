import Foundation
import SwiftData

@Model
final class Summary {
    var id: UUID
    var overview: String
    var insights: String
    var outline: String
    var keyDecisions: String = ""
    var openQuestions: String = ""
    var attendees: [String] = []
    var templateName: String?
    
    var meeting: Meeting?

    init(id: UUID = UUID(), overview: String = "", insights: String = "", outline: String = "", keyDecisions: String = "", openQuestions: String = "", attendees: [String] = [], templateName: String? = nil) {
        self.id = id
        self.overview = overview
        self.insights = insights
        self.outline = outline
        self.keyDecisions = keyDecisions
        self.openQuestions = openQuestions
        self.attendees = attendees
        self.templateName = templateName
    }
}
