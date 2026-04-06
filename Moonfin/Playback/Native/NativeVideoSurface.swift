import AVFoundation
import CoreMedia
import UIKit

final class NativeVideoSurface {
    private weak var hostView: UIView?
    private let displayLayer = AVSampleBufferDisplayLayer()
    private let enqueueQueue = DispatchQueue(label: "nativeVideoSurface.enqueue")
    private var pendingFrames: [(CVPixelBuffer, CMTime, CMTime)] = []
    private let lock = NSLock()
    private var requestingData = false

    init() {
        displayLayer.backgroundColor = UIColor.black.cgColor
        displayLayer.videoGravity = .resizeAspect
        displayLayer.preventsDisplaySleepDuringVideoPlayback = true
    }

    func attach(to view: UIView) {
        hostView = view
        displayLayer.removeFromSuperlayer()
        view.layer.addSublayer(displayLayer)
        updateLayout()
        beginRequestingMediaData()
    }

    func updateLayout() {
        guard let hostView else { return }
        let bounds = hostView.bounds
        if displayLayer.frame != bounds {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            displayLayer.frame = bounds
            CATransaction.commit()
        }
    }

    func enqueue(pixelBuffer: CVPixelBuffer, pts: CMTime, duration: CMTime) {
        lock.lock()
        pendingFrames.append((pixelBuffer, pts, duration))
        lock.unlock()
    }

    func flush() {
        lock.lock()
        pendingFrames.removeAll()
        lock.unlock()
        displayLayer.flush()
    }

    func teardown() {
        stopRequestingMediaData()
        lock.lock()
        pendingFrames.removeAll()
        lock.unlock()
        displayLayer.flush()
        displayLayer.removeFromSuperlayer()
        hostView = nil
    }

    func setVideoGravity(_ mode: ZoomMode) {
        switch mode {
        case .fit:
            displayLayer.videoGravity = .resizeAspect
        case .autoCrop:
            displayLayer.videoGravity = .resizeAspectFill
        case .stretch:
            displayLayer.videoGravity = .resize
        }
    }

    // MARK: - Pull-based enqueue

    private func beginRequestingMediaData() {
        guard !requestingData else { return }
        requestingData = true
        displayLayer.requestMediaDataWhenReady(on: enqueueQueue) { [weak self] in
            self?.drainPendingFrames()
        }
    }

    private func stopRequestingMediaData() {
        requestingData = false
        displayLayer.stopRequestingMediaData()
    }

    private func drainPendingFrames() {
        while displayLayer.isReadyForMoreMediaData {
            lock.lock()
            guard !pendingFrames.isEmpty else {
                lock.unlock()
                return
            }
            let (pixelBuffer, pts, duration) = pendingFrames.removeFirst()
            lock.unlock()

            guard let sampleBuffer = makeSampleBuffer(from: pixelBuffer, pts: pts, duration: duration) else {
                continue
            }
            displayLayer.enqueue(sampleBuffer)
        }
    }

    // MARK: - CMSampleBuffer creation

    private func makeSampleBuffer(from pixelBuffer: CVPixelBuffer, pts: CMTime, duration: CMTime) -> CMSampleBuffer? {
        var formatDescription: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard status == noErr, let fmt = formatDescription else { return nil }

        var timing = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        let result = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: fmt,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard result == noErr else { return nil }
        return sampleBuffer
    }
}
