@preconcurrency import ScreenCaptureKit
import AVFAudio
import CoreMedia

final class SystemAudioCapture: @unchecked Sendable {
    var onAudioBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?

    private var stream: SCStream?
    private var delegate: StreamDelegate?

    static let audioFormat = AVAudioFormat(
        standardFormatWithSampleRate: 48000,
        channels: 2
    )!

    // Always exclude our own process to prevent feedback loops
    private static let selfBundleID = "com.amenocturne.micmixer"

    func start(excluding bundleIDs: Set<String>) async throws {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else { return }

        var allExcluded = bundleIDs
        allExcluded.insert(Self.selfBundleID)
        let excludedApps = content.applications.filter {
            allExcluded.contains($0.bundleIdentifier)
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

        // Exclude self even in include mode
        let includedApps = content.applications.filter {
            bundleIDs.contains($0.bundleIdentifier)
                && $0.bundleIdentifier != Self.selfBundleID
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

        // SCStream requires video config even for audio-only
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.showsCursor = false

        let cb = onAudioBuffer
        let streamDelegate = StreamDelegate(onAudioBuffer: cb)
        self.delegate = streamDelegate

        let newStream = SCStream(filter: filter, configuration: config, delegate: streamDelegate)
        try newStream.addStreamOutput(streamDelegate, type: .screen, sampleHandlerQueue: .global())
        try newStream.addStreamOutput(streamDelegate, type: .audio, sampleHandlerQueue: .global())

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
        guard type == .audio,
              let pcmBuffer = sampleBuffer.toPCMBuffer() else { return }
        onAudioBuffer?(pcmBuffer)
    }
}

private extension CMSampleBuffer {
    // Copies audio data into a self-contained AVAudioPCMBuffer.
    // Using CMSampleBufferCopyPCMDataIntoAudioBufferList instead of
    // CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer to avoid
    // a use-after-free: the latter writes pointers into a CMBlockBuffer
    // that gets freed when the local ref goes out of scope.
    func toPCMBuffer() -> AVAudioPCMBuffer? {
        guard let formatDesc = formatDescription,
              dataBuffer != nil else { return nil }

        let audioFormat = AVAudioFormat(cmAudioFormatDescription: formatDesc)
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(self))
        guard frameCount > 0,
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount)
        else { return nil }
        pcmBuffer.frameLength = frameCount

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            self,
            at: 0,
            frameCount: Int32(frameCount),
            into: pcmBuffer.mutableAudioBufferList
        )
        guard status == noErr else { return nil }
        return pcmBuffer
    }
}
