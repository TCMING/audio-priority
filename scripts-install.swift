import Foundation

let files = FileManager.default
let home = files.homeDirectoryForCurrentUser
let service = "local.audio-priority"
let domain = "gui/\(getuid())"
let support = home.appendingPathComponent("Library/Application Support/AudioPriority")
let applications = home.appendingPathComponent("Applications")
let agents = home.appendingPathComponent("Library/LaunchAgents")
let target = applications.appendingPathComponent("音频自动切换.app")
let plist = agents.appendingPathComponent(service + ".plist")

func launchctl(_ arguments: [String]) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

for directory in [support, applications, agents] {
    try files.createDirectory(at: directory, withIntermediateDirectories: true)
}
guard let source = ProcessInfo.processInfo.environment["AUDIO_PRIORITY_SOURCE"] else {
    fatalError("Run install.sh")
}
guard !files.fileExists(atPath: target.path) else {
    fatalError("Application already exists at \(target.path). Back it up or remove it before installing.")
}
try files.copyItem(at: URL(fileURLWithPath: source), to: target)
let config = support.appendingPathComponent("priorities.json")
let agent: [String: Any] = [
    "Label": service,
    "ProgramArguments": [target.appendingPathComponent("Contents/MacOS/audio-priority").path],
    "RunAtLoad": true,
    "KeepAlive": true,
    "ThrottleInterval": 10,
    "ProcessType": "Background",
    "StandardOutPath": "/dev/null",
    "StandardErrorPath": "/dev/null"
]
_ = try launchctl(["bootout", domain + "/" + service])
try PropertyListSerialization.data(fromPropertyList: agent, format: .xml, options: 0).write(to: plist, options: .atomic)
guard try launchctl(["bootstrap", domain, plist.path]) == 0 else { fatalError("Could not start service") }
print("Installed at \(target.path)")
print("Device order: \(config.path)")
