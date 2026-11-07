import Foundation
let files = FileManager.default
let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
let service = ServiceManager(service: "local.audio-priority.install-check")
guard !files.fileExists(atPath: service.agent.path), !service.running else { fatalError("Test label already exists") }
try files.createDirectory(at: root.appendingPathComponent("Test.bundle/Contents/MacOS"), withIntermediateDirectories: true)
let bundleURL = root.appendingPathComponent("Test.bundle")
let executable = bundleURL.appendingPathComponent("Contents/MacOS/audio-priority")
try Data("#!/bin/sh\nexec /bin/sleep 60\n".utf8).write(to: executable)
try files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
let info: [String: Any] = ["CFBundleExecutable": "audio-priority", "CFBundleIdentifier": "local.audio-priority.install-check", "CFBundleVersion": "1", "CFBundlePackageType": "BNDL"]
try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: bundleURL.appendingPathComponent("Contents/Info.plist"))
defer {
    if service.running { _ = service.stop() }
    try? files.removeItem(at: service.agent)
    try? files.removeItem(at: root)
}
let bundle = Bundle(url: bundleURL)!
try service.configure(bundle: bundle)
assert(service.running, "First launch did not start service")
let saved = try Data(contentsOf: service.agent)
try service.configure(bundle: bundle)
assert(try! Data(contentsOf: service.agent) == saved)
assert(service.stop())
try service.configure(bundle: bundle)
assert(!service.running, "Repeated launch resumed a paused service")
assert(service.start())
print("PASS first-launch setup, idempotency, pause preservation and restart")
