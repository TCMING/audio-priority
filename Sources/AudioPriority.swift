import CoreAudio
import Darwin
import Foundation

let store = SettingsStore()
func apply() -> Bool {
    do {
        let devices = outputDevices()
        let settings = try store.update(connected: devices)
        guard let best = bestOutput(devices, settings: settings) else { return true }
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice] {
            if audioNumber(audioSystem, selector) == best.id { continue }
            var address = property(selector)
            var id = best.id
            let result = AudioObjectSetPropertyData(audioSystem, &address, 0, nil, 4, &id)
            guard result == noErr else { return false }
        }
        return true
    } catch {
        fputs("Settings error: \(error)\n", stderr)
        return false
    }
}

if CommandLine.arguments.contains("--list") {
    let devices = outputDevices()
    for device in devices {
        let current = audioNumber(audioSystem, kAudioHardwarePropertyDefaultOutputDevice) == device.id
        print("\(current ? "*" : " ") \(device.name) [\(device.uid)]")
    }
    exit(0)
}
if CommandLine.arguments.contains("--once") { exit(apply() ? 0 : 1) }

try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
let queue = DispatchQueue(label: "local.audio-priority.events")
var pending: DispatchWorkItem?
func schedule() {
    pending?.cancel()
    let task = DispatchWorkItem {
        if !apply() { queue.asyncAfter(deadline: .now() + 1) { _ = apply() } }
    }
    pending = task
    queue.asyncAfter(deadline: .now() + 0.4, execute: task)
}
let listener: AudioObjectPropertyListenerBlock = { _, _ in schedule() }
for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice] {
    var address = property(selector)
    guard AudioObjectAddPropertyListenerBlock(audioSystem, &address, queue, listener) == noErr else { exit(1) }
}
// Watch the directory because atomic saves replace the configuration file.
let descriptor = open(supportURL.path, O_EVTONLY)
guard descriptor >= 0 else { exit(1) }
let watcher = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: queue)
watcher.setEventHandler { schedule() }
watcher.setCancelHandler { close(descriptor) }
watcher.resume()
queue.async { _ = apply() }
dispatchMain()
