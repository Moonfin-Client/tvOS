import Foundation

protocol SessionRepositoryProtocol {
    var isAuthenticated: Bool { get }
    func restoreSession() async
    func destroyCurrentSession()
}
