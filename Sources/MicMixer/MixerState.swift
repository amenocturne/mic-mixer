import Foundation
import Combine

enum FilterMode: String, CaseIterable, Sendable {
    case exclude
    case include
}

final class MixerState: ObservableObject, @unchecked Sendable {
    @Published var isActive = false {
        didSet {
            save()
            Task { @MainActor in self.syncEngine() }
        }
    }

    @Published var systemVolume: Float = 0.7 {
        didSet {
            mixer.setSystemVolume(systemVolume)
            save()
        }
    }

    @Published var micVolume: Float = 1.0 {
        didSet {
            mixer.setMicVolume(micVolume)
            save()
        }
    }

    @Published var filterMode: FilterMode = .exclude {
        didSet {
            save()
            Task { @MainActor in self.restartCapture() }
        }
    }

    @Published var excludedAppBundleIDs: Set<String> = [] {
        didSet {
            save()
            if filterMode == .exclude { Task { @MainActor in self.restartCapture() } }
        }
    }

    @Published var includedAppBundleIDs: Set<String> = [] {
        didSet {
            save()
            if filterMode == .include { Task { @MainActor in self.restartCapture() } }
        }
    }

    @Published var selectedOutputDeviceUID: String = "" {
        didSet {
            save()
            if isActive {
                // Full deactivate + activate cycle to pick up the new device
                capture.stop()
                mixer.stop()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(200))
                    self.syncEngine()
                }
            } else if selectedOutputDevice != nil {
                errorMessage = nil
            }
        }
    }

    @Published var errorMessage: String?

    var outputDevices: [AudioDevice] { listOutputDevices() }

    var selectedOutputDevice: AudioDevice? {
        guard !selectedOutputDeviceUID.isEmpty else { return nil }
        return outputDevices.first { $0.uid == selectedOutputDeviceUID }
            ?? findBlackHoleDevice()
    }

    let appMonitor = AppMonitor()
    let mixer = AudioMixer()
    private let capture = SystemAudioCapture()

    init() {
        restore()
        capture.onAudioBuffer = { [mixer] buffer in
            mixer.scheduleSystemAudio(buffer)
        }

        if findBlackHoleDevice() == nil && outputDevices.isEmpty {
            errorMessage = "No virtual audio device found. Install BlackHole to use MicMixer."
        }
    }

    // MARK: - App filter toggling

    func isAppSelected(_ bundleID: String) -> Bool {
        switch filterMode {
        case .exclude: excludedAppBundleIDs.contains(bundleID)
        case .include: includedAppBundleIDs.contains(bundleID)
        }
    }

    func toggleApp(_ bundleID: String) {
        switch filterMode {
        case .exclude:
            if excludedAppBundleIDs.contains(bundleID) {
                excludedAppBundleIDs.remove(bundleID)
            } else {
                excludedAppBundleIDs.insert(bundleID)
            }
        case .include:
            if includedAppBundleIDs.contains(bundleID) {
                includedAppBundleIDs.remove(bundleID)
            } else {
                includedAppBundleIDs.insert(bundleID)
            }
        }
    }

    // MARK: - Engine sync

    // Not async — runs on MainActor, dispatches capture start separately
    // Never sets isActive from here — avoids re-entrant didSet loops
    private func syncEngine() {
        if isActive {
            guard let device = selectedOutputDevice else {

                errorMessage = "No output device. Install BlackHole."
                return
            }

            errorMessage = nil
            mixer.stop()
            capture.stop()
            do {
                try mixer.start(outputDeviceID: device.id)

                mixer.setSystemVolume(systemVolume)
                mixer.setMicVolume(micVolume)
                Task { @MainActor in
                    do {
                        try await self.startCapture()

                    } catch {

                        self.errorMessage = "Capture: \(error.localizedDescription)"
                    }
                }
            } catch {

                errorMessage = "Engine: \(error.localizedDescription)"
            }
        } else {

            capture.stop()
            mixer.stop()
            errorMessage = nil
        }
    }

    // Only restarts the audio engine with a new output device — capture keeps running
    private func reconnectOutput() {
        guard let device = selectedOutputDevice else { return }

        mixer.stop()
        do {
            try mixer.start(outputDeviceID: device.id)
            mixer.setSystemVolume(systemVolume)
            mixer.setMicVolume(micVolume)
        } catch {

            errorMessage = "Output device error: \(error.localizedDescription)"
        }
    }

    private func startCapture() async throws {
        switch filterMode {
        case .exclude:
            try await capture.start(excluding: excludedAppBundleIDs)
        case .include:
            try await capture.start(including: includedAppBundleIDs)
        }
    }

    private func restartCapture() {
        guard isActive else { return }
        capture.stop()
        Task { @MainActor in
            do {
                try await self.startCapture()
            } catch {
                self.errorMessage = "Failed to restart capture: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Persistence

    nonisolated(unsafe) private static let defaults = UserDefaults.standard
    private static let keyPrefix = "MicMixer."

    private func save() {
        let d = Self.defaults
        d.set(systemVolume, forKey: Self.keyPrefix + "systemVolume")
        d.set(micVolume, forKey: Self.keyPrefix + "micVolume")
        d.set(filterMode.rawValue, forKey: Self.keyPrefix + "filterMode")
        d.set(Array(excludedAppBundleIDs), forKey: Self.keyPrefix + "excludedApps")
        d.set(Array(includedAppBundleIDs), forKey: Self.keyPrefix + "includedApps")
        d.set(selectedOutputDeviceUID, forKey: Self.keyPrefix + "outputDeviceUID")
    }

    private func restore() {
        let d = Self.defaults
        let prefix = Self.keyPrefix

        if d.object(forKey: prefix + "systemVolume") != nil {
            systemVolume = d.float(forKey: prefix + "systemVolume")
        }
        if d.object(forKey: prefix + "micVolume") != nil {
            micVolume = d.float(forKey: prefix + "micVolume")
        }
        if let mode = d.string(forKey: prefix + "filterMode"),
           let fm = FilterMode(rawValue: mode) {
            filterMode = fm
        }
        if let excluded = d.stringArray(forKey: prefix + "excludedApps") {
            excludedAppBundleIDs = Set(excluded)
        }
        if let included = d.stringArray(forKey: prefix + "includedApps") {
            includedAppBundleIDs = Set(included)
        }
        if let uid = d.string(forKey: prefix + "outputDeviceUID") {
            selectedOutputDeviceUID = uid
        } else if let bh = findBlackHoleDevice() {
            selectedOutputDeviceUID = bh.uid
        }

        // isActive always starts as false — user must toggle on manually
    }
}
