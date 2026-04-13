@preconcurrency import ScreenCaptureKit
import AVFAudio
import CoreMedia

@MainActor
final class SystemAudioCapture {
    var onAudioBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?

    private var stream: SCStream?
    private var delegate: StreamDelegate?

    static let audioFormat = AVAudioFormat(
        standardFormatWithSampleRate: 48000,
        channels: 2
    )!

    func start(excluding bundleIDs: Set<String>) async throws {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else { return }

        let excludedApps = content.applications.filter {
            bundleIDs.contains($0.bundleIdentifier)
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApps,
            exceptingWindows: []
        )
        try await startStream(filter: filter)
    }

    func start(including bundleIDs: Set<String>) async throws {
        guard !bundleIDs.isEmpty else { return }

        let content = try await SCShareableContent.current
        guard let display = content.displays.first else { return }

        let includedApps = content.applications.filter {
            bundleIDs.contains($0.bundleIdentifier)
        }
        let filter = SCContentFilter(
            display: display,
            including: includedApps,
            exceptingWindows: []
        )
        try await startStream(filter: filter)
    }

    func stop() {
        stream?.stopCapture()
        stream = nil
        delegate = nil
    }

    private func startStream(filter: SCContentFilter) async throws {
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = 48000
        config.channelCount = 2

        // ScreenCaptureKit requires a video stream; use minimum dimensions to discard frames cheaply.
        config.width = 1
        config.height = 1
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let cb = onAudioBuffer
        let streamDelegate = StreamDelegate(onAudioBuffer: cb)
        self.delegate = streamDelegate

        let newStream = SCStream(filter: filter, configuration: config, delegate: streamDelegate)
        try newStream.addStreamOutput(streamDelegate, type: .audio, sampleHandlerQueue: nil)
        try await newStream.startCapture()
        self.stream = newStream
    }
}

private final class StreamDelegate: NSObject, SCStreamDelegate, SCStreamOutput, @unchecked Sendable {
    private let onAudioBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?

    init(onAudioBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?) {
        self.onAudioBuffer = onAudioBuffer
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {}

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio else { return }
        guard let pcmBuffer = sampleBuffer.toPCMBuffer() else { return }
        onAudioBuffer?(pcmBuffer)
    }
}

private extension CMSampleBuffer {
    func toPCMBuffer() -> AVAudioPCMBuffer? {
        guard let formatDesc = formatDescription,
              dataBuffer != nil else { return nil }

        let audioFormat = AVAudioFormat(cmAudioFormatDescription: formatDesc)
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(self))
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else { return nil }
        pcmBuffer.frameLength = frameCount

        var blockBufferRef: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            self,
            bufferListSizeNeededOut: nil,
            bufferListOut: pcmBuffer.mutableAudioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size
                + MemoryLayout<AudioBuffer>.size * Int(audioFormat.channelCount - 1),
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBufferRef
        )
        guard status == noErr else { return nil }
        return pcmBuffer
    }
}
