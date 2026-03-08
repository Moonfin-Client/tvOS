import Foundation

protocol PlaybackManagerProtocol {
    var isPlaying: Bool { get }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }

    func play(url: URL) async
    func pause()
    func resume()
    func stop()
    func seek(to position: TimeInterval)
    func setRate(_ rate: Float)
    func setAudioTrack(_ index: Int32)
    func setSubtitleTrack(_ index: Int32)
    func addSubtitle(url: URL)
}
