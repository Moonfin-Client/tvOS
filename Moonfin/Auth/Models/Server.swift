import Foundation

struct Server: Codable, Identifiable {
    let id: UUID
    var name: String
    var address: String
    var version: String?
    var loginDisclaimer: String?
    var dateLastAccessed: Date?
}
