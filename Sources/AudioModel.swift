import CoreAudio
import Darwin
import Foundation

let audioSystem = AudioObjectID(kAudioObjectSystemObject)
let supportURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AudioPriority")
let configurationURL = supportURL.appendingPathComponent("priorities.json")

func property(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

func audioNumber(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
    var address = property(selector, scope: scope)
    var value: UInt32 = 0
    var size: UInt32 = 4
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
    return value
}

func audioString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
    var address = property(selector)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
    return value?.takeRetainedValue() as String?
}

struct OutputDevice {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

func outputDevices() -> [OutputDevice] {
    var address = property(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(audioSystem, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    let result = ids.withUnsafeMutableBytes {
        AudioObjectGetPropertyData(audioSystem, &address, 0, nil, &size, $0.baseAddress!)
    }
    guard result == noErr else { return [] }
    return ids.compactMap { id in
        var streams = property(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
        var bytes: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &bytes) == noErr,
              bytes > 0, audioNumber(id, kAudioDevicePropertyDeviceIsAlive) == 1,
              audioNumber(id, kAudioDevicePropertyDeviceCanBeDefaultDevice, scope: kAudioDevicePropertyScopeOutput) == 1,
              let name = audioString(id, kAudioObjectPropertyName),
              let uid = audioString(id, kAudioDevicePropertyDeviceUID) else { return nil }
        return OutputDevice(id: id, uid: uid, name: name)
    }
}

struct SavedDevice: Codable, Equatable {
    var uid: String
    var name: String
}

struct Settings: Codable, Equatable {
    var version = 1
    var devices: [SavedDevice]
}

// Both processes update the same file. Lock the full read/merge/write transaction.
struct SettingsStore {
    let directory: URL
    init(directory: URL = supportURL) { self.directory = directory }

    func update(connected: [OutputDevice], orderedUIDs: [String]? = nil) throws -> Settings {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = open(directory.appendingPathComponent("settings.lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw POSIXError(.EACCES) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw POSIXError(.EIO) }
        defer { flock(descriptor, LOCK_UN) }
        let url = directory.appendingPathComponent("priorities.json")
        let data = try? Data(contentsOf: url)
        var settings: Settings
        if let data {
            if let current = try? JSONDecoder().decode(Settings.self, from: data) {
                guard current.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
                settings = current
            } else {
                let names = try JSONDecoder().decode([String].self, from: data)
                settings = Settings(devices: names.map { name in
                    SavedDevice(uid: connected.first(where: { $0.name == name })?.uid ?? "legacy:" + name, name: name)
                })
            }
        } else {
            // On first use prefer the currently selected output, then discover all others.
            let current = audioNumber(audioSystem, kAudioHardwarePropertyDefaultOutputDevice)
            let sorted = connected.sorted { ($0.id == current ? 0 : 1) < ($1.id == current ? 0 : 1) }
            settings = Settings(devices: sorted.map { SavedDevice(uid: $0.uid, name: $0.name) })
        }
        let previous = settings
        for device in connected {
            if let index = settings.devices.firstIndex(where: { $0.uid == device.uid || $0.uid == "legacy:" + device.name }) {
                settings.devices[index] = SavedDevice(uid: device.uid, name: device.name)
            } else {
                settings.devices.append(SavedDevice(uid: device.uid, name: device.name))
            }
        }
        var seen = Set<String>()
        settings.devices = settings.devices.filter { seen.insert($0.uid).inserted }
        if let orderedUIDs {
            let lookup = Dictionary(uniqueKeysWithValues: settings.devices.map { ($0.uid, $0) })
            let requested = orderedUIDs.compactMap { lookup[$0] }
            settings.devices = requested + settings.devices.filter { !orderedUIDs.contains($0.uid) }
        }
        if data == nil || settings != previous || (data.flatMap { try? JSONDecoder().decode(Settings.self, from: $0) }) == nil {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(settings).write(to: url, options: .atomic)
        }
        return settings
    }
}

func bestOutput(_ devices: [OutputDevice], settings: Settings) -> OutputDevice? {
    for saved in settings.devices {
        if let device = devices.first(where: { $0.uid == saved.uid }) { return device }
    }
    return nil
}
