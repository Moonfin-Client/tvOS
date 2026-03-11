import Foundation

enum NetworkError: LocalizedError, Equatable {
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

    var isUnavailable: Bool {
        switch self {
        case .serverUnavailable: return true
        case .networkError(let error):
            if let urlError = error as? URLError {
                return [.timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed]
                    .contains(urlError.code)
            }
            return false
        default: return false
        }
    }

    static func == (lhs: NetworkError, rhs: NetworkError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidURL, .invalidURL): return true
        case (.unauthorized, .unauthorized): return true
        case (.serverUnavailable, .serverUnavailable): return true
        case (.httpError(let a, _), .httpError(let b, _)): return a == b
        case (.decodingError, .decodingError): return true
        case (.networkError, .networkError): return true
        default: return false
        }
    }
}
