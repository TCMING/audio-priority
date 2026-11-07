import AppKit
import CoreAudio

final class Controller: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 410), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    let table = NSTableView()
    let message = NSTextField(labelWithString: "")
    let toggle = NSButton(title: "", target: nil, action: nil)
    let pasteboardType = NSPasteboard.PasteboardType("local.audio-priority.device")
    let store = SettingsStore()
    var settings = Settings(devices: [])
    var devices: [OutputDevice] = []
    var listener: AudioObjectPropertyListenerBlock?
    let serviceManager = ServiceManager()
    var running: Bool { serviceManager.running }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let applicationURL = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let userApplications = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path + "/"
        guard applicationURL.path.hasPrefix("/Applications/") || applicationURL.path.hasPrefix(userApplications) else {
            let notice = NSAlert()
            notice.messageText = "请先安装到应用程序"
            notice.informativeText = "将“音频自动切换”拖到“应用程序”文件夹，再从那里打开。"
            notice.addButton(withTitle: "打开应用程序文件夹")
            notice.addButton(withTitle: "关闭")
            NSApp.activate(ignoringOtherApps: true)
            if notice.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
            }
            NSApp.terminate(nil)
            return
        }
        do {
            _ = try store.update(connected: outputDevices())
            try serviceManager.configure()
        } catch {
            let notice = NSAlert()
            notice.messageText = "自动配置未完成"
            notice.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            notice.runModal()
        }
        window.title = "音频自动切换"
        window.minSize = NSSize(width: 520, height: 340)
        let root = NSView()
        window.contentView = root
        let title = NSTextField(labelWithString: "声音输出优先级")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        let detail = NSTextField(wrappingLabelWithString: "拖动设备调整顺序，越靠上越优先。顺序自动保存并立即生效。\n新设备自动加入末尾，断开的设备保留原有顺序。")
        detail.textColor = .secondaryLabelColor
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        table.headerView = nil
        table.rowHeight = 48
        table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("device"))
        column.width = 520
        table.addTableColumn(column)
        table.dataSource = self
        table.delegate = self
        table.registerForDraggedTypes([pasteboardType])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        scroll.documentView = table
        toggle.target = self
        toggle.action = #selector(toggleService)
        toggle.bezelStyle = .rounded
        message.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, detail, scroll, message, toggle])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        root.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 140)
        ])
        let menu = NSMenu()
        let item = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "停用并移除登录后台项", action: #selector(removeService), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "退出控制窗口", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu
        menu.addItem(item)
        NSApp.mainMenu = menu
        listener = { [weak self] _, _ in self?.refresh() }
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
            var address = property(selector)
            AudioObjectAddPropertyListenerBlock(audioSystem, &address, .main, listener!)
        }
        refresh()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func refresh() {
        devices = outputDevices()
        do {
            settings = try store.update(connected: devices)
            table.reloadData()
            updateStatus()
        } catch { message.stringValue = "保存失败：\(error.localizedDescription)" }
    }
    func updateStatus() {
        let active = running
        toggle.title = active ? "暂停自动切换" : "启用自动切换"
        message.stringValue = active ? "已启用 · 关闭窗口后后台继续运行" : "已暂停 · 下次登录将自动启用"
    }
    @objc func toggleService() {
        let succeeded = running ? serviceManager.stop() : serviceManager.start()
        guard succeeded else {
            message.stringValue = "服务操作失败，请在系统设置中检查登录项。"
            return
        }
        updateStatus()
    }
    @objc func removeService() {
        let notice = NSAlert()
        notice.messageText = "停用登录后台项？"
        notice.informativeText = "自动切换将停止。设备排序仍会保留，退出后可删除 App。再次打开 App 会重新配置后台服务。"
        notice.addButton(withTitle: "取消")
        notice.addButton(withTitle: "停用并退出")
        guard notice.runModal() == .alertSecondButtonReturn else { return }
        if running && !serviceManager.stop() {
            message.stringValue = "无法停止后台服务，请稍后重试。"
            return
        }
        do {
            if FileManager.default.fileExists(atPath: serviceManager.agent.path) {
                try FileManager.default.removeItem(at: serviceManager.agent)
            }
            NSApp.terminate(nil)
        } catch { message.stringValue = "移除登录项失败：\(error.localizedDescription)" }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { settings.devices.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let saved = settings.devices[row]
        let connected = devices.first { $0.uid == saved.uid }
        let selected = connected.map { audioNumber(audioSystem, kAudioHardwarePropertyDefaultOutputDevice) == $0.id } ?? false
        let text = NSTextField(labelWithString: "≡   \(row + 1).  \(saved.name)    \(selected ? "● 正在使用" : connected == nil ? "○ 未连接" : "● 已连接")")
        text.textColor = connected == nil ? .secondaryLabelColor : .labelColor
        text.font = .systemFont(ofSize: 14)
        let cell = NSTableCellView()
        cell.addSubview(text)
        text.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(settings.devices[row].uid, forType: pasteboardType)
        return item
    }
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
        guard info.draggingPasteboard.string(forType: pasteboardType) != nil else { return [] }
        tableView.setDropRow(row, dropOperation: .above)
        return .move
    }
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let uid = info.draggingPasteboard.string(forType: pasteboardType),
              let original = settings.devices.firstIndex(where: { $0.uid == uid }) else { return false }
        var order = settings.devices.map(\.uid)
        order.remove(at: original)
        let target = min(max(0, row > original ? row - 1 : row), order.count)
        order.insert(uid, at: target)
        do {
            settings = try store.update(connected: outputDevices(), orderedUIDs: order)
            table.reloadData()
            table.selectRowIndexes(IndexSet(integer: target), byExtendingSelection: false)
            updateStatus()
            return true
        } catch {
            message.stringValue = "保存失败：\(error.localizedDescription)"
            return false
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil)
        return true
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
    app.applicationIconImage = icon
}
let controller = Controller()
app.delegate = controller
app.run()
