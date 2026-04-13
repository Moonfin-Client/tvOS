import Foundation
import os

actor NetworkErrorHandler {
    static let shared = NetworkErrorHandler()
    private let logger = Logger(subsystem: "org.moonfin.appletv", category: "NetworkErrorHandler")

    struct RetryPolicy {
        var maxAttempts: Int = 3
        var baseDelay: TimeInterval = 1.0
        var maxDelay: TimeInterval = 30.0
        var retryableStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504]
    }

    static let defaultPolicy = RetryPolicy()
    static let aggressivePolicy = RetryPolicy(maxAttempts: 5, baseDelay: 0.5)
    static let conservativePolicy = RetryPolicy(maxAttempts: 2, baseDelay: 2.0, maxDelay: 60.0)

    func execute<T>(
        policy: RetryPolicy = defaultPolicy,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for attempt in 0..<policy.maxAttempts {
            do {
                return try await operation()
            } catch let error as NetworkError {
                lastError = error
                guard isRetryable(error, policy: policy) else { throw error }
                let delay = calculateDelay(attempt: attempt, policy: policy)
                logger.warning("Retry \(attempt + 1)/\(policy.maxAttempts) after \(delay, format: .fixed(precision: 1))s: \(error.localizedDescription)")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch let error as URLError {
                lastError = error
                guard isRetryableURLError(error) else {
                    throw NetworkError.networkError(error)
                }
                let delay = calculateDelay(attempt: attempt, policy: policy)
                logger.warning("Retry \(attempt + 1)/\(policy.maxAttempts) after \(delay, format: .fixed(precision: 1))s: \(error.localizedDescription)")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                throw error
            }
        }

        throw lastError ?? NetworkError.serverUnavailable
    }

    func executeOptional<T>(
        policy: RetryPolicy = RetryPolicy(maxAttempts: 1),
        operation: @Sendable () async throws -> T
    ) async -> T? {
        do {
            return try await execute(policy: policy, operation: operation)
        } catch {
            logger.error("Operation failed (non-critical): \(error.localizedDescription)")
            return nil
        }
    }

    private func isRetryable(_ error: NetworkError, policy: RetryPolicy) -> Bool {
        switch error {
        case .serverUnavailable:
            return true
        case .httpError(let code, _):
            return policy.retryableStatusCodes.contains(code)
        case .networkError(let underlying):
            if let urlError = underlying as? URLError {
                return isRetryableURLError(urlError)
            }
            return false
        case .unauthorized, .invalidURL, .decodingError:
            return false
        }
    }

    private func isRetryableURLError(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet,
             .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    private func calculateDelay(attempt: Int, policy: RetryPolicy) -> TimeInterval {
        let delay = policy.baseDelay * pow(2.0, Double(attempt))
        let jitter = Double.random(in: 0...0.5)
        return min(delay + jitter, policy.maxDelay)
    }
}

extension NetworkError {
    private static func l(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    }

    private static func l(_ key: String, _ args: CVarArg...) -> String {
        String(format: l(key), arguments: args)
    }

    var isRetryable: Bool {
        switch self {
        case .serverUnavailable: return true
        case .httpError(let code, _): return [408, 429, 500, 502, 503, 504].contains(code)
        case .networkError(let error):
            if let urlError = error as? URLError {
                switch urlError.code {
                case .timedOut, .networkConnectionLost, .notConnectedToInternet,
                     .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                    return true
                default:
                    return false
                }
            }
            return false
        case .unauthorized, .invalidURL, .decodingError: return false
        }
    }

    var userFacingMessage: String {
        switch self {
        case .invalidURL:
            return Self.l("network_user_invalid_server_address")
        case .httpError(let code, _):
            switch code {
            case 401: return Self.l("network_user_session_expired")
            case 403: return Self.l("network_user_access_denied")
            case 404: return Self.l("network_user_content_not_found")
            case 408: return Self.l("network_user_request_timed_out")
            case 429: return Self.l("network_user_too_many_requests")
            case 500...599: return Self.l("network_user_server_error")
            default: return Self.l("network_user_request_failed_http", code)
            }
        case .decodingError:
            return Self.l("network_user_unexpected_server_response")
        case .networkError(let error):
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet: return Self.l("network_user_no_internet")
                case .timedOut: return Self.l("network_user_connection_timed_out")
                case .cannotFindHost, .cannotConnectToHost: return Self.l("network_user_unable_to_reach_server")
                case .secureConnectionFailed: return Self.l("network_user_secure_connection_failed")
                default: return Self.l("network_user_network_error")
                }
            }
            return Self.l("network_user_network_error")
        case .unauthorized:
            return Self.l("network_user_session_expired")
        case .serverUnavailable:
            return Self.l("network_user_server_is_unavailable")
        }
    }
}
