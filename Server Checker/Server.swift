import Foundation

struct Server: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var host: String // IP or hostname
    var port: Int = 80
}

enum ServerStatus: String, Codable {
    case unknown
    case online
    case offline
}
