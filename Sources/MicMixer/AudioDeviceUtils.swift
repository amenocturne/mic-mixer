import CoreAudio
import AudioToolbox
import Foundation

enum AudioDeviceError: Error {
    case propertyQueryFailed(OSStatus)
    case invalidDevice
    case setPropertyFailed(OSStatus)
}

struct AudioDevice: Identifiable, Hashable, Sendable {
    let id: AudioDeviceID
    let name: String
    let uid: String
}

private func getPropertyDataSize(
    objectID: AudioObjectID,
    address: AudioObjectPropertyAddress
) throws -> UInt32 {
    var addr = address
    var size: UInt32 = 0
    let status = AudioObjectGetPropertyDataSize(objectID, &addr, 0, nil, &size)
    guard status == noErr else { throw AudioDeviceError.propertyQueryFailed(status) }
    return size
}

private func getStringProperty(
    deviceID: AudioDeviceID,
    selector: AudioObjectPropertySelector
) -> String? {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var cfString: CFString? = nil
    var size = UInt32(MemoryLayout<CFString?>.size)
    let status = withUnsafeMutablePointer(to: &cfString) { ptr in
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, ptr)
    }
    guard status == noErr, let result = cfString else { return nil }
    return result as String
}

private func hasOutputStreams(deviceID: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreams,
        mScope: kAudioObjectPropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
    return status == noErr && size > 0
}

func listOutputDevices() -> [AudioDevice] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    var size: UInt32 = 0
    let systemObject = AudioObjectID(kAudioObjectSystemObject)
    guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr,
          size > 0 else { return [] }

    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &deviceIDs) == noErr
    else { return [] }

    return deviceIDs.compactMap { deviceID in
        guard hasOutputStreams(deviceID: deviceID),
              let name = getStringProperty(deviceID: deviceID, selector: kAudioObjectPropertyName),
              let uid = getStringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID)
        else { return nil }
        return AudioDevice(id: deviceID, name: name, uid: uid)
    }
}

func findBlackHoleDevice() -> AudioDevice? {
    listOutputDevices().first { $0.name.contains("BlackHole") }
}

func setOutputDevice(engineOutput: AudioUnit, deviceID: AudioDeviceID) throws {
    var deviceID = deviceID
    let status = AudioUnitSetProperty(
        engineOutput,
        kAudioOutputUnitProperty_CurrentDevice,
        kAudioUnitScope_Global,
        0,
        &deviceID,
        UInt32(MemoryLayout<AudioDeviceID>.size)
    )
    guard status == noErr else { throw AudioDeviceError.setPropertyFailed(status) }
}
