import Foundation

enum NetworkError: LocalizedError {
    case invalidURL
    case httpError(statusCode: Int, data: Data?)
    case decodingError(Error)
    case networkError(Error)
    case unauthorized
    case serverUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .httpError(let code, _):
            return "HTTP error \(code)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .networkError(let error):
            return error.localizedDescription
        case .unauthorized:
            return "Unauthorized"
        case .serverUnavailable:
            return "Server unavailable"
        }
    }
}
