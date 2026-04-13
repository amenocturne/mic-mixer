import AVFAudio
import CoreAudio

@MainActor
final class AudioMixer {
    private let engine = AVAudioEngine()
    // Accessed from SCStream callback thread — scheduleBuffer is thread-safe
    nonisolated(unsafe) private let systemPlayerNode = AVAudioPlayerNode()
    private let systemMixerNode = AVAudioMixerNode()
    private let micMixerNode = AVAudioMixerNode()

    private(set) var isRunning = false

    init() {
        engine.attach(systemPlayerNode)
        engine.attach(systemMixerNode)
        engine.attach(micMixerNode)
    }

    func start(outputDeviceID: AudioDeviceID) throws {
        let outputUnit = engine.outputNode.audioUnit!
        try setOutputDevice(engineOutput: outputUnit, deviceID: outputDeviceID)

        let systemFormat = SystemAudioCapture.audioFormat
        engine.connect(systemPlayerNode, to: systemMixerNode, format: systemFormat)
        engine.connect(systemMixerNode, to: engine.mainMixerNode, format: systemFormat)

        let micFormat = engine.inputNode.outputFormat(forBus: 0)
        engine.connect(engine.inputNode, to: micMixerNode, format: micFormat)
        engine.connect(micMixerNode, to: engine.mainMixerNode, format: micFormat)

        try engine.start()
        systemPlayerNode.play()
        isRunning = true
    }

    func stop() {
        systemPlayerNode.stop()
        engine.stop()
        isRunning = false
    }

    func setSystemVolume(_ volume: Float) {
        systemMixerNode.outputVolume = volume
    }

    func setMicVolume(_ volume: Float) {
        micMixerNode.outputVolume = volume
    }

    nonisolated func scheduleSystemAudio(_ buffer: AVAudioPCMBuffer) {
        systemPlayerNode.scheduleBuffer(buffer)
    }
}
