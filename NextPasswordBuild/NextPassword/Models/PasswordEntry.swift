import Foundation

struct PasswordEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var site: String
    var username: String
    var password: String
    var link: String
    var notes: String
    var createdAt = Date()
}
