import SwiftUI
import ServiceManagement
import ScreenCaptureKit
import AVFAudio

@main
struct MicMixerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // All UI managed by AppDelegate — this body is never re-evaluated
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let state = MixerState()
    private var iconCancellable: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "MicMixer")
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 620)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(state: state)
                .frame(width: 300)
        )

        // Update icon via Combine — no SwiftUI body re-evaluation
        iconCancellable = state.$isActive.receive(on: DispatchQueue.main).sink { [weak self] active in
            let name = active ? "waveform.circle.fill" : "waveform.circle"
            self?.statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "MicMixer")
        }

        // Request permissions upfront so the first toggle works
        requestPermissions()
    }

    private func requestPermissions() {
        // Screen Recording — triggers TCC prompt if not granted
        Task {
            _ = try? await SCShareableContent.current
        }
        // Microphone — triggers TCC prompt if not granted
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        let activeItem = NSMenuItem(
            title: state.isActive ? "Deactivate" : "Activate",
            action: #selector(toggleActive),
            keyEquivalent: ""
        )
        activeItem.target = self
        menu.addItem(activeItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit MicMixer",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleActive() {
        state.isActive.toggle()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

struct PopoverView: View {
    @ObservedObject var state: MixerState
    @State private var searchText = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var filteredApps: [AppInfo] {
        let apps = state.appMonitor.apps
        if searchText.isEmpty { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = state.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }

            Toggle(isOn: $state.isActive) {
                Text("Active")
                    .font(.headline)
            }
            .toggleStyle(.switch)

            LiveMeters(state: state)

            Divider()

            Picker("Mode", selection: $state.filterMode) {
                Text("Exclude").tag(FilterMode.exclude)
                Text("Include").tag(FilterMode.include)
            }
            .pickerStyle(.segmented)

            Text(state.filterMode == .exclude
                ? "All audio captured, checked apps excluded"
                : "Only checked apps' audio captured")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Search apps...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if let first = filteredApps.first {
                        state.toggleApp(first.bundleIdentifier)
                    }
                }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredApps) { app in
                        AppRow(app: app, isSelected: state.isAppSelected(app.bundleIdentifier)) {
                            state.toggleApp(app.bundleIdentifier)
                        }
                    }
                }
            }
            .frame(height: 300)

            Divider()

            HStack {
                Text("Output")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $state.selectedOutputDeviceUID) {
                    Text("None").tag("")
                    ForEach(state.outputDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 180)
            }

            Divider()

            HStack {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .font(.caption)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !enabled
                        }
                    }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
    }
}

// Rolling window averager — shows the mean of recent peaks for smoother meters
final class LevelSmoother {
    private var buffer: [Float]
    private var index = 0
    private var filled = false

    init(windowSize: Int = 5) {
        buffer = [Float](repeating: 0, count: windowSize)
    }

    func update(peak: Float) -> Float {
        buffer[index] = peak
        index += 1
        if index >= buffer.count {
            index = 0
            filled = true
        }
        let count = filled ? buffer.count : index
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count { sum += buffer[i] }
        return sum / Float(count)
    }
}

struct LiveMeters: View {
    @ObservedObject var state: MixerState
    @State private var micSmoother = LevelSmoother()
    @State private var sysSmoother = LevelSmoother()

    var body: some View {
        TimelineView(.animation) { _ in
            let micPeak = state.mixer.peakMicLevel.withLock { v in let r = v; v *= 0.5; return r }
            let sysPeak = state.mixer.peakSystemLevel.withLock { v in let r = v; v *= 0.5; return r }
            let sysLevel = sysSmoother.update(peak: sysPeak) * state.systemVolume
            let micLevel = micSmoother.update(peak: micPeak) * state.micVolume
            VStack(spacing: 8) {
                VolumeSlider(label: "System Audio", value: $state.systemVolume, level: sysLevel)
                VolumeSlider(label: "Microphone", value: $state.micVolume, level: micLevel)
            }
        }
    }
}

struct VolumeSlider: View {
    let label: String
    @Binding var value: Float
    var level: Float = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.caption)
                Spacer()
                Text("\(Int(value * 100))%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: 0...2)
            LevelMeter(level: level)
        }
    }
}

struct LevelMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.quaternary)
                RoundedRectangle(cornerRadius: 2)
                    .fill(level > 0.8 ? Color.red : level > 0.5 ? Color.yellow : Color.green)
                    .frame(width: geo.size.width * CGFloat(level))
            }
        }
        .frame(height: 4)
    }
}

struct AppRow: View {
    let app: AppInfo
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 20, height: 20)
                Text(app.name)
                    .lineLimit(1)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
    }
}
