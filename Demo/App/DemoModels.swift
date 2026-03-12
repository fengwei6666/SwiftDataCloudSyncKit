import Foundation
import SwiftData

@Model
final class DemoWork {
    var id: String
    var name: String
    var notes: String
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        notes: String,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.updatedAt = updatedAt
    }
}
