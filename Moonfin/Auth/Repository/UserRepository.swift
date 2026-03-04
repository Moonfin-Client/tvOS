import Foundation
import Combine

protocol UserRepositoryProtocol: AnyObject {
    var currentUser: CurrentValueSubject<ServerUser?, Never> { get }
    func setCurrentUser(_ user: ServerUser?)
}

final class UserRepository: UserRepositoryProtocol {
    let currentUser = CurrentValueSubject<ServerUser?, Never>(nil)

    func setCurrentUser(_ user: ServerUser?) {
        currentUser.send(user)
    }
}
