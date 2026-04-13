import AVFAudio
import CoreAudio
import Accelerate

final class AudioMixer: @unchecked Sendable {
    // Main engine: system audio → mixer → BlackHole output
    private let engine = AVAudioEngine()
    nonisolated(unsafe) private let systemPlayerNode = AVAudioPlayerNode()
    private let systemMixerNode = AVAudioMixerNode()
    private let micMixerNode = AVAudioMixerNode()
    nonisolated(unsafe) private let micPlayerNode = AVAudioPlayerNode()

    // Separate engine for mic — stays on default input device,
    // not affected by setting main engine's output to BlackHole
    private let micEngine = AVAudioEngine()

    private(set) var isRunning = false
    private var graphBuilt = false

    let peakMicLevel = OSAllocatedUnfairLock(initialState: Float(0))
    let peakSystemLevel = OSAllocatedUnfairLock(initialState: Float(0))

    private var configObserver: Any?

    init() {
        engine.attach(systemPlayerNode)
        engine.attach(systemMixerNode)
        engine.attach(micMixerNode)
        engine.attach(micPlayerNode)

        // Restart mic engine when audio devices change (headphones plugged in/out)
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: micEngine, queue: .main
        ) { [weak self] _ in
            guard let self, self.isRunning else { return }
            writeLog("[MicMixer] Audio config changed, restarting mic engine")
            try? self.micEngine.start()
            self.micPlayerNode.play()
        }
    }

    func start(outputDeviceID: AudioDeviceID) throws {
        let outputUnit = engine.outputNode.audioUnit!
        try setOutputDevice(engineOutput: outputUnit, deviceID: outputDeviceID)

        if !graphBuilt {
            // System audio path
            let systemFormat = SystemAudioCapture.audioFormat
            engine.connect(systemPlayerNode, to: systemMixerNode, format: systemFormat)
            engine.connect(systemMixerNode, to: engine.mainMixerNode, format: systemFormat)

            // Mic path — mic buffers arrive from micEngine via micPlayerNode
            let micFormat = micEngine.inputNode.outputFormat(forBus: 0)
            engine.connect(micPlayerNode, to: micMixerNode, format: micFormat)
            engine.connect(micMixerNode, to: engine.mainMixerNode, format: micFormat)

            // Mic tap on separate engine — captures from default mic device
            let micLock = self.peakMicLevel
            let player = self.micPlayerNode
            nonisolated(unsafe) var running = { self.isRunning }
            micEngine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
                let level = rmsLevel(from: buffer)
                micLock.withLock { $0 = max($0, level) }
                if running() {
                    player.scheduleBuffer(buffer)
                }
            }

            graphBuilt = true
        }

        try engine.start()
        systemPlayerNode.play()
        micPlayerNode.play()

        try micEngine.start()
        isRunning = true
    }

    func stop() {
        isRunning = false
        micEngine.stop()
        systemPlayerNode.stop()
        micPlayerNode.stop()
        engine.stop()
    }

    func setSystemVolume(_ volume: Float) {
        systemMixerNode.outputVolume = volume
    }

    func setMicVolume(_ volume: Float) {
        micMixerNode.outputVolume = volume
    }

    nonisolated func scheduleSystemAudio(_ buffer: AVAudioPCMBuffer) {
        guard isRunning else { return }
        let level = rmsLevel(from: buffer)
        peakSystemLevel.withLock { $0 = max($0, level) }
        systemPlayerNode.scheduleBuffer(buffer)
    }
}

private func rmsLevel(from buffer: AVAudioPCMBuffer) -> Float {
    guard let channelData = buffer.floatChannelData else { return 0 }
    let frameLength = Int(buffer.frameLength)
    guard frameLength > 0 else { return 0 }

    var rms: Float = 0
    vDSP_rmsqv(channelData[0], 1, &rms, vDSP_Length(frameLength))
    let db = 20 * log10(max(rms, 1e-7))
    return max(0, min(1, (db + 50) / 50))
}
