import SwiftUI
import ServiceManagement

@main
struct MicMixerApp: App {
    @State private var state = MixerState()

    var body: some Scene {
        MenuBarExtra(
            "MicMixer",
            systemImage: state.isActive ? "waveform.circle.fill" : "waveform.circle"
        ) {
            PopoverView(state: state)
                .frame(width: 300)
        }
        .menuBarExtraStyle(.window)
    }
}

struct PopoverView: View {
    @Bindable var state: MixerState
    @State private var searchText = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var filteredApps: [AppInfo] {
        let apps = state.appMonitor.apps
        if searchText.isEmpty { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Error banner
            if let error = state.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }

            // Master toggle
            Toggle(isOn: $state.isActive) {
                Text("Active")
                    .font(.headline)
            }
            .toggleStyle(.switch)

            // Volume sliders
            VStack(spacing: 8) {
                VolumeSlider(label: "System Audio", value: $state.systemVolume)
                VolumeSlider(label: "Microphone", value: $state.micVolume)
            }

            Divider()

            // Filter mode
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

            // App list
            TextField("Search apps...", text: $searchText)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredApps) { app in
                        AppRow(app: app, isSelected: state.isAppSelected(app.bundleIdentifier)) {
                            state.toggleApp(app.bundleIdentifier)
                        }
                    }
                }
            }
            .frame(maxHeight: 200)

            Divider()

            // Output device
            HStack {
                Text("Output")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $state.selectedOutputDeviceUID) {
                    ForEach(state.outputDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 180)
            }

            Divider()

            // Footer
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
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.caption)
            }
        }
        .padding(16)
    }
}

struct VolumeSlider: View {
    let label: String
    @Binding var value: Float

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
            Slider(value: $value, in: 0...1)
        }
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
