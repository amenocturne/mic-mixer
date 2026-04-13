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

That's it. No configuration files, no audio graphs, no sessions.

## Features

**Menu bar native** — Lives in the menu bar. No dock icon, no windows. Click to open, click away to dismiss.

**Per-app audio filtering** — Two modes: *Exclude* (capture everything except checked apps) or *Include* (capture only checked apps). Each mode remembers its own selections.

**Independent volume control** — System audio and microphone each get their own slider. Mix to taste.

**Persistent state** — Volumes, filter mode, app selections, output device — all saved. Quit and relaunch, everything's exactly as you left it.

**Launch at login** — One toggle. Uses the modern macOS Login Items API.

## Prerequisites

- macOS 26 (Tahoe), Apple Silicon
- [BlackHole](https://github.com/ExistentialAudio/BlackHole) virtual audio driver installed

MicMixer captures and mixes audio, but needs BlackHole (or similar) as the virtual output device that video call apps read as a "microphone."

## Install

```bash
git clone <repo-url>
cd mic-mixer
just install
```

This builds a release binary, wraps it in an `.app` bundle, codesigns it, and copies it to `/Applications/`.

Or run without installing:

```bash
just run
```

### First launch

macOS will prompt for two permissions:
- **Screen & System Audio Recording** — for capturing app audio via ScreenCaptureKit
- **Microphone** — for mixing in your mic

Both are required.

## Architecture

```
ScreenCaptureKit (per-app audio)
        │
        ▼ CMSampleBuffer → AVAudioPCMBuffer
        │
  AVAudioPlayerNode → systemMixerNode ─┐
                                        ├─► mainMixerNode → BlackHole device
  AVAudioEngine.inputNode → micMixerNode ┘
        │
        ▼
  Zoom reads BlackHole as "microphone"
```

Six files, no abstractions:

| File | Role |
| --- | --- |
| `MicMixerApp.swift` | SwiftUI entry point, MenuBarExtra, popover UI |
| `MixerState.swift` | Observable state hub, owns all components |
| `AudioMixer.swift` | AVAudioEngine graph wiring and gain control |
| `SystemAudioCapture.swift` | SCStream audio-only capture + format bridge |
| `AppMonitor.swift` | Running apps list via NSWorkspace notifications |
| `AudioDeviceUtils.swift` | Core Audio device enumeration |

## License

MIT
