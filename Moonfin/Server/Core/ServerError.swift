import Foundation

enum ServerError: LocalizedError {
    case unsupported(String)
    case notConfigured(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unsupported(let message): return message
        case .notConfigured(let message): return message
        case .invalidResponse: return "Invalid server response"
        }
    }
}
