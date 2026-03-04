import Foundation

protocol PlaybackManagerProtocol {
    func play(url: URL) async
    func pause()
    func stop()
    func seek(to position: TimeInterval)
}
