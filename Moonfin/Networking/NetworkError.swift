import Foundation

enum NetworkError: LocalizedError, Equatable {
    case invalidURL
    case httpError(statusCode: Int, data: Data?)
    case decodingError(Error)
    case networkError(Error)
    case unauthorized
    case serverUnavailable

    private static func l(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    }

    private static func l(_ key: String, _ args: CVarArg...) -> String {
        String(format: l(key), arguments: args)
    }

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return Self.l("network_error_invalid_url")
        case .httpError(let code, _):
            return Self.l("network_error_http_error", code)
        case .decodingError(let error):
            return Self.l("network_error_decoding_error", error.localizedDescription)
        case .networkError(let error):
            return error.localizedDescription
        case .unauthorized:
            return Self.l("network_error_unauthorized")
        case .serverUnavailable:
            return Self.l("network_error_server_unavailable")
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
