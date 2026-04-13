import AVFAudio
import CoreAudio
import Accelerate
import os

final class AudioMixer: @unchecked Sendable {
    private let engine = AVAudioEngine()
    nonisolated(unsafe) private let systemPlayerNode = AVAudioPlayerNode()
    private let systemMixerNode = AVAudioMixerNode()
    private let micMixerNode = AVAudioMixerNode()

    private(set) var isRunning = false

    // Atomic peak levels — written from audio threads, read from UI via TimelineView
    let peakMicLevel = OSAllocatedUnfairLock(initialState: Float(0))
    let peakSystemLevel = OSAllocatedUnfairLock(initialState: Float(0))

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

        // Mic level tap
        let peakMic = peakMicLevel
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: micFormat) { buffer, _ in
            let level = rmsLevel(from: buffer)
            peakMic.withLock { $0 = max($0, level) }
        }

        try engine.start()
        systemPlayerNode.play()
        isRunning = true
    }

    func stop() {
        if isRunning {
            engine.inputNode.removeTap(onBus: 0)
        }
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

    private var sysLogCount = 0
    nonisolated func scheduleSystemAudio(_ buffer: AVAudioPCMBuffer) {
        let level = rmsLevel(from: buffer)
        peakSystemLevel.withLock { $0 = max($0, level) }
        // Log first few buffers
        if sysLogCount < 3 {
            sysLogCount += 1
            let hasFloat = buffer.floatChannelData != nil
            var peak: Float = 0
            if let d = buffer.floatChannelData {
                for i in 0..<min(Int(buffer.frameLength), 100) { peak = max(peak, abs(d[0][i])) }
            }
            writeLog("scheduleSystemAudio: rms=\(level), frames=\(buffer.frameLength), hasFloat=\(hasFloat), peakSample=\(peak)")
        }
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
    // -40dB → 0, 0dB → 1
    return max(0, min(1, (db + 40) / 40))
}
