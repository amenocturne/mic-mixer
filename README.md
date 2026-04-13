<h1 align="center">MicMixer</h1>

<h3 align="center"><i>TWO SLIDERS. DONE.</i></h3>

<p align="center">Menu bar app that mixes system audio + microphone into a virtual device for video calls.</p>

## Why

Sharing system audio in Zoom/Meet/Teams on macOS requires either:

- **Loopback** ($99) or **Soundshine** ($8) — paid
- **Aggregate device hack** with BlackHole — easy to misconfigure, no volume control
- **Audio Hijack** — node graph overkill for "play Spotify into the call"

None of these give you a simple "pick apps, set volumes, go" experience. MicMixer does.

## How it works

1. Click the menu bar icon
2. Toggle on, set your system audio and mic volumes
3. Pick which apps to include or exclude
4. In Zoom: select BlackHole as your microphone
5. Participants hear your system audio + voice

No configuration files, no audio graphs, no sessions.

## Features

**Menu bar native** — Lives in the menu bar. No dock icon, no windows. Click to open, click away to dismiss. Right-click for quick actions.

**Per-app audio filtering** — Two modes: *Exclude* (capture everything except checked apps) or *Include* (capture only checked apps). Each mode remembers its own selections. Search field with enter-to-select for quick filtering.

**Independent volume control** — System audio and microphone each get their own slider (0–200%). Live RMS level meters show what's actually going through.

**Output device picker** — Route mixed audio to any output device, not just BlackHole. Switching devices while active reconnects automatically.

**Persistent state** — Volumes, filter mode, app selections, output device — all saved via UserDefaults. Quit and relaunch, everything's exactly as you left it.

**Launch at login** — One toggle. Uses the modern macOS SMAppService API.

## Prerequisites

- macOS 15+ (Sequoia), Apple Silicon
- [BlackHole](https://github.com/ExistentialAudio/BlackHole) virtual audio driver installed

MicMixer captures and mixes audio, but needs BlackHole (or similar) as the virtual output device that video call apps read as a "microphone."

## Install

### Homebrew

```bash
brew install amenocturne/tap/micmixer
```

### Download

Grab the latest `.app` from [Releases](https://github.com/amenocturne/mic-mixer/releases), unzip, and drag to `/Applications/`.

### Build from source

```bash
git clone https://github.com/amenocturne/mic-mixer.git
cd mic-mixer
just install
```

This builds a release binary, wraps it in an `.app` bundle, codesigns it ad-hoc, and copies it to `/Applications/`.

### First launch

macOS will prompt for two permissions:

- **Screen & System Audio Recording** — for capturing app audio via ScreenCaptureKit
- **Microphone** — for mixing in your mic

Both are required. Must run as `.app` bundle for TCC permissions.

## Architecture

```
ScreenCaptureKit (per-app audio)
        │
        ▼ CMSampleBuffer → AVAudioPCMBuffer
        │
  AVAudioPlayerNode → systemMixerNode ─┐
                                        ├─► mainMixerNode → output device
  micEngine.inputNode → micMixerNode ───┘
        │
        ▼
  Zoom reads BlackHole as "microphone"
```

Dual-engine design: the main engine handles system audio mixing and output routing, while a separate mic engine stays on the default input device — unaffected by output device changes.

Seven files, no external dependencies:

| File | Role |
| --- | --- |
| `MicMixerApp.swift` | SwiftUI entry point, MenuBarExtra, popover UI, level meters |
| `MixerState.swift` | Observable state hub, owns all components, UserDefaults persistence |
| `AudioMixer.swift` | Dual AVAudioEngine graph: system audio + mic → mixed output |
| `SystemAudioCapture.swift` | SCStream audio-only capture, CMSampleBuffer → PCM conversion |
| `AppMonitor.swift` | Running apps list via NSWorkspace notifications |
| `AudioDeviceUtils.swift` | Core Audio C API device enumeration and output routing |
| `Package.swift` | SPM config, system framework linking |

### Tech stack

Swift 6 · SwiftUI · ScreenCaptureKit · AVFAudio · CoreAudio · AppKit · Swift Package Manager

## Build commands

```
just build          swift build -c release
just bundle         build + create .app bundle + codesign
just run            bundle + open .app
just install        bundle + copy to /Applications
just release 1.2.0  bundle + upload to GitHub Releases
just clean          remove build artifacts
just fmt            swift-format
just lint           swift-format --lint
```

## License

MIT
