# MicMixer

Menu bar app that mixes system audio + microphone into a BlackHole virtual device for use as mic input in video calls.

## Tech Stack

- Swift 6, SwiftUI, macOS 26+
- ScreenCaptureKit (system audio capture)
- AVFAudio (mic capture, mixing, output routing)
- Core Audio (device enumeration, output device selection)
- Swift Package Manager (no Xcode project)

## Architecture

```
MicMixerApp     → SwiftUI @main, MenuBarExtra with .window style popover
MixerState      → @Observable state hub, owns AudioMixer + SystemAudioCapture + AppMonitor
AudioMixer      → AVAudioEngine: systemPlayerNode → systemMixer → mainMixer ← micMixer ← inputNode
SystemAudioCapture → SCStream audio-only capture, CMSampleBuffer → AVAudioPCMBuffer conversion
AppMonitor      → NSWorkspace running apps + launch/terminate notifications
AudioDeviceUtils → Core Audio C API: list output devices, find BlackHole, set output device
```

Data flow: SCStream → PCM buffer → AVAudioPlayerNode.scheduleBuffer (thread-safe, no MainActor bounce)

## Commands

```
just build    # swift build -c release
just bundle   # build + create .app bundle + codesign
just run      # bundle + open .app
just install  # bundle + copy to /Applications
just clean    # remove build artifacts
just fmt      # swift-format
just lint     # swift-format --lint
```

## Key Design Decisions

- **Audio-only SCStream**: ScreenCaptureKit requires video config even for audio-only. Video set to 1x1 @ 1fps, frames discarded.
- **nonisolated scheduleBuffer**: `AVAudioPlayerNode.scheduleBuffer` is thread-safe, called directly from SCStream callback without MainActor dispatch to avoid Sendable issues.
- **Filter mode**: Include/Exclude with separate remembered `Set<String>` per mode. Switching modes preserves each mode's selections.
- **Filter rebuild**: Changing app selection stops SCStream, rebuilds SCContentFilter, starts new stream. Brief ~50-100ms audio gap.
- **No unit tests**: Heavy system integration (audio devices, permissions, ScreenCaptureKit). All testing is manual.

## Permissions

- "Screen & System Audio Recording" (ScreenCaptureKit)
- "Microphone" (AVAudioEngine input)
- Must run as .app bundle for TCC on macOS 26

## Dependencies

- BlackHole virtual audio driver must be installed separately
