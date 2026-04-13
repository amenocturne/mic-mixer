import Foundation
import Observation

enum FilterMode: String, CaseIterable {
    case exclude
    case include
}

@MainActor
@Observable
final class MixerState {
    var isActive = false {
        didSet { Task { await syncEngine() } }
    }

    var systemVolume: Float = 0.7 {
        didSet {
            mixer.setSystemVolume(systemVolume)
            save()
        }
    }

    var micVolume: Float = 1.0 {
        didSet {
            mixer.setMicVolume(micVolume)
            save()
        }
    }

    var filterMode: FilterMode = .exclude {
        didSet {
            save()
            Task { await restartCapture() }
        }
    }

    var excludedAppBundleIDs: Set<String> = [] {
        didSet {
            save()
            if filterMode == .exclude { Task { await restartCapture() } }
        }
    }

    var includedAppBundleIDs: Set<String> = [] {
        didSet {
            save()
            if filterMode == .include { Task { await restartCapture() } }
        }
    }

    var selectedOutputDeviceUID: String = "" {
        didSet {
            save()
            if isActive { Task { await syncEngine() } }
        }
    }

    var launchAtLogin = false

    var outputDevices: [AudioDevice] { listOutputDevices() }

    var selectedOutputDevice: AudioDevice? {
        outputDevices.first { $0.uid == selectedOutputDeviceUID }
            ?? findBlackHoleDevice()
    }

    var errorMessage: String?

    let appMonitor = AppMonitor()
    private let mixer = AudioMixer()
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

    private func syncEngine() async {
        if isActive {
            guard let device = selectedOutputDevice else {
                errorMessage = "No output device selected. Install BlackHole to use MicMixer."
                isActive = false
                return
            }
            errorMessage = nil
            mixer.stop()
            capture.stop()
            do {
                try mixer.start(outputDeviceID: device.id)
                mixer.setSystemVolume(systemVolume)
                mixer.setMicVolume(micVolume)
                try await startCapture()
            } catch {
                errorMessage = "Failed to start audio engine: \(error.localizedDescription)"
                isActive = false
            }
        } else {
            capture.stop()
            mixer.stop()
            errorMessage = nil
        }
        save()
    }

    private func startCapture() async throws {
        switch filterMode {
        case .exclude:
            try await capture.start(excluding: excludedAppBundleIDs)
        case .include:
            try await capture.start(including: includedAppBundleIDs)
        }
    }

    private func restartCapture() async {
        guard isActive else { return }
        capture.stop()
        do {
            try await startCapture()
        } catch {
            errorMessage = "Failed to restart capture: \(error.localizedDescription)"
        }
    }

    // MARK: - Persistence

    private static let defaults = UserDefaults.standard
    private static let keyPrefix = "MicMixer."

    private func save() {
        let d = Self.defaults
        d.set(isActive, forKey: Self.keyPrefix + "isActive")
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

        // Restore active state last — triggers engine start
        if d.bool(forKey: prefix + "isActive") {
            isActive = true
        }
    }
}
