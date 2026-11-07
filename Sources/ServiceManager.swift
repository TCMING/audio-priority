import Foundation

struct ServiceManager {
    var service = "local.audio-priority"
    let domain = "gui/\(getuid())"
    var agent: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/" + service + ".plist")
    }

    func run(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run(); process.waitUntilExit(); return process.terminationStatus }
        catch { return -1 }
    }
    var running: Bool { run(["print", domain + "/" + service]) == 0 }
    func start() -> Bool { run(["bootstrap", domain, agent.path]) == 0 }
    func stop() -> Bool { run(["bootout", domain + "/" + service]) == 0 }

    // Called by the installed app on first launch and after an update.
    // An unchanged installation preserves a pause during the current login.
    func configure(bundle: Bundle = .main) throws {
        guard let helper = bundle.executableURL?.deletingLastPathComponent().appendingPathComponent("audio-priority"),
              FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw NSError(domain: service, code: 1, userInfo: [NSLocalizedDescriptionKey: "应用文件不完整，请重新安装。"])
        }
        try FileManager.default.createDirectory(at: agent.deletingLastPathComponent(), withIntermediateDirectories: true)
        let version = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        let dictionary: [String: Any] = [
            "Label": service,
            "ProgramArguments": [helper.path],
            "EnvironmentVariables": ["AUDIO_PRIORITY_BUILD": version],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ThrottleInterval": 10,
            "ProcessType": "Background",
            "StandardOutPath": "/dev/null",
            "StandardErrorPath": "/dev/null"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
        let old = FileManager.default.fileExists(atPath: agent.path) ? try Data(contentsOf: agent) : nil
        if old == data { return }
        let wasRunning = running
        if wasRunning && !stop() {
            throw NSError(domain: service, code: 2, userInfo: [NSLocalizedDescriptionKey: "无法停止旧版后台服务，请稍后重试。"])
        }
        do {
            try data.write(to: agent, options: .atomic)
            if (old == nil || wasRunning) && !start() {
                throw NSError(domain: service, code: 3, userInfo: [NSLocalizedDescriptionKey: "后台服务启动失败，请检查系统的登录项设置。"])
            }
        } catch {
            if let old {
                try? old.write(to: agent, options: .atomic)
                if wasRunning { _ = start() }
            } else {
                try? FileManager.default.removeItem(at: agent)
            }
            throw error
        }
    }
}
