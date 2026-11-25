import AppKit
import SwiftUI
import ApplicationServices
import Combine

final class ClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PanelHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class PanelState: ObservableObject {
    @Published var query = ""
    @Published var filter: ClipFilter = .history
    @Published var selectedID: String?
    @Published var message: String?
    @Published var focusRequest = UUID()
    @Published var batch = BatchPasteSelection()
    func visible(_ store: ClipStore) -> [Clip] {
        store.clips.filter { clip in
            let matches: Bool
            switch filter { case .history: matches = true; case .starred: matches = clip.starred; case .board(let id): matches = clip.boards.contains(id); case .kind(.image): matches = clip.hasImagePreview; case .kind(let kind): matches = clip.kind == kind }
            return matches && (query.isEmpty || clip.text.localizedStandardContains(query) || clip.source.localizedStandardContains(query))
        }
    }
}

final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var store: ClipStore!
    var clipboard: ClipboardService!
    let state = PanelState()
    let hotKey = HotKey()
    var panel: ClipboardPanel!
    private var status: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var target: PasteDestination?
    private var lastExternalApplication: NSRunningApplication?
    private let pasteCoordinator = PasteCoordinator()
    private var keyMonitor: Any?
    private var outsideMonitor: Any?
    private var subscriptions = Set<AnyCancellable>()
    private var panelShownAt: TimeInterval = 0
    private var historyCleaner: HistoryCleanupService?
    private(set) var isRecordingShortcut = false
    static var demo = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = .clipNestIcon
        Preferences.shared.$theme.removeDuplicates().sink { mode in NSApp.appearance = mode.appearance }.store(in: &subscriptions)
        installMenu()
        rememberExternalApplication(NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification).sink { [weak self] notification in
            self?.rememberExternalApplication(notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }.store(in: &subscriptions)
        do {
            let dir: URL
            if Self.demo { dir = FileManager.default.temporaryDirectory.appendingPathComponent("ClipNest-Demo-\(ProcessInfo.processInfo.processIdentifier)") }
            else { dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("ClipNest", isDirectory: true) }
            store = try ClipStore(url: dir.appendingPathComponent("history.sqlite"))
        } catch { let alert = NSAlert(); alert.messageText = "剪藏无法启动"; alert.informativeText = error.localizedDescription; alert.runModal(); NSApp.terminate(nil); return }
        clipboard = ClipboardService(store: store)
        historyCleaner = HistoryCleanupService(store: store); historyCleaner?.start()
        if Self.demo { seedDemo() } else { clipboard.start() }
        store.loadFilePreviews()
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "剪藏")
        status.button?.target = self; status.button?.action = #selector(statusClicked)
        status.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        Preferences.shared.$showMenuBarIcon.removeDuplicates().sink { [weak self] visible in self?.status?.isVisible = visible }.store(in: &subscriptions)
        panel = ClipboardPanel(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 390), styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.hidesOnDeactivate = false; panel.isFloatingPanel = true; panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = PanelHostingView(rootView: PanelView(store: store, state: state, controller: self))
        hotKey.onPress = { [weak self] in guard let self, !self.isRecordingShortcut else { return }; self.toggle() }
        restoreShortcut()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }; return self.handleKey(event)
        }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return }
            let statusFrame = self.status.button.flatMap { button in button.window?.convertToScreen(button.convert(button.bounds, to: nil)) }
            if PanelDismissalPolicy.shouldDismiss(visible: panel.isVisible, panelFrame: panel.frame, statusFrame: statusFrame, click: NSEvent.mouseLocation, eventTime: event.timestamp, shownAt: self.panelShownAt) { self.hide() }
        }
        show()
    }
    func applicationWillTerminate(_ notification: Notification) { clipboard?.stop(); historyCleaner?.stop() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return false }
    private func restoreShortcut() {
        if !hotKey.register(Preferences.shared.shortcut) {
            Preferences.shared.showMenuBarIcon = true
            state.message = "\(Preferences.shared.shortcut.display) 已被占用。已显示菜单栏图标，请在设置中更换快捷键。"
        }
    }
    func beginShortcutRecording() { isRecordingShortcut = true; hotKey.suspend() }
    @discardableResult func finishShortcutRecording(_ shortcut: KeyboardShortcut?) -> String? {
        defer { isRecordingShortcut = false }
        guard let shortcut else { restoreShortcut(); return nil }
        if let error = shortcut.validationError { restoreShortcut(); return error }
        guard hotKey.register(shortcut) else { restoreShortcut(); return "这组快捷键已被占用或无法注册，原快捷键未更改。" }
        Preferences.shared.saveShortcut(shortcut)
        state.message = "呼出快捷键已更新为 \(shortcut.display)"
        return nil
    }
    func setMenuBarVisible(_ visible: Bool) -> String? {
        if !visible && !hotKey.isRegistered { return "当前快捷键不可用，请先设置有效快捷键，再隐藏菜单栏图标。" }
        Preferences.shared.showMenuBarIcon = visible
        return nil
    }
    private func installMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu(title: "剪藏")
        let settings = NSMenuItem(title: "剪藏设置…", action: #selector(settingsFromMenu), keyEquivalent: ","); settings.target = self
        appMenu.addItem(settings); appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出剪藏", action: #selector(quit), keyEquivalent: "q"); quitItem.target = self; appMenu.addItem(quitItem)
        appItem.submenu = appMenu; menu.addItem(appItem)
        let editItem = NSMenuItem(); let edit = NSMenu(title: "编辑")
        for (title, selector, key) in [("撤销", Selector(("undo:")), "z"), ("剪切", #selector(NSText.cut(_:)), "x"), ("复制", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"), ("全选", #selector(NSText.selectAll(_:)), "a")] { edit.addItem(NSMenuItem(title: title, action: selector, keyEquivalent: key)) }
        editItem.submenu = edit; menu.addItem(editItem); NSApp.mainMenu = menu
    }
    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let title = NSMenuItem(title: "剪藏 · Clipboard, collected.", action: nil, keyEquivalent: ""); menu.addItem(title)
            menu.addItem(NSMenuItem.separator())
            for (name, action, key) in [("打开剪藏", #selector(toggleFromMenu), ""), (Preferences.shared.paused ? "继续记录" : "暂停记录", #selector(pauseFromMenu), ""), ("设置…", #selector(settingsFromMenu), ","), ("退出剪藏", #selector(quit), "q")] {
                let item = NSMenuItem(title: name, action: action, keyEquivalent: key); item.target = self; menu.addItem(item)
            }
            status.menu = menu; status.button?.performClick(nil); status.menu = nil
        } else { toggle() }
    }
    @objc private func toggleFromMenu() { toggle() }
    @objc private func pauseFromMenu() { Preferences.shared.paused.toggle() }
    @objc private func settingsFromMenu() { showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
    func toggle() { panel.isVisible ? hide() : show() }
    private func rememberExternalApplication(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.bundleIdentifier != Bundle.main.bundleIdentifier, app.activationPolicy == .regular else { return }
        lastExternalApplication = app
    }
    func show(preservingTarget: Bool = false) {
        pasteCoordinator.cancel()
        let front = NSWorkspace.shared.frontmostApplication
        if !preservingTarget {
            rememberExternalApplication(front)
            if let app = lastExternalApplication, !app.isTerminated { target = MacPasteEnvironment.destination(for: app) }
            else { target = nil }
        }
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main!
        let frame = screen.visibleFrame
        let width = min(1160.0, frame.width - 32)
        panel.setFrame(NSRect(x: frame.midX - width / 2, y: frame.minY + 18, width: width, height: min(390, frame.height - 40)), display: true)
        state.focusRequest = UUID()
        panelShownAt = ProcessInfo.processInfo.systemUptime
        panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func hide() { panel?.orderOut(nil) }
    func toggleBatchMode() {
        state.message = nil
        if state.batch.isActive { state.batch.stop(); state.focusRequest = UUID() }
        else {
            state.batch.start()
            let clips = state.visible(store)
            if !clips.contains(where: { $0.id == state.selectedID && BatchPasteSelection.canSelect($0) }) {
                state.selectedID = clips.first(where: BatchPasteSelection.canSelect)?.id
            }
            panel.makeFirstResponder(panel.contentView)
        }
    }
    func select(_ clip: Clip) {
        state.selectedID = clip.id
        if state.batch.isActive {
            guard BatchPasteSelection.canSelect(clip) else { state.message = "多选拼接仅支持文字和链接。"; return }
            state.batch.toggle(clip); state.message = nil
        }
    }
    func pasteBatch(copyOnly: Bool = false) {
        do {
            let joined = try state.batch.joinedText(from: store.clips)
            let merged = Clip.make(kind: .text, text: joined, source: "剪藏", bundleID: Bundle.main.bundleIdentifier ?? "")
            paste(merged, copyOnly: copyOnly, batchCount: state.batch.orderedIDs.count)
        } catch { state.message = error.localizedDescription }
    }
    func paste(_ clip: Clip, copyOnly: Bool = false, batchCount: Int? = nil) {
        guard clipboard.copy(clip) else { state.message = "无法复制这条记录，请重试。"; return }
        if copyOnly {
            state.message = batchCount.map { "已用空格拼接并复制 \($0) 条，按 ⌘V 即可粘贴" } ?? "已复制，按 ⌘V 即可粘贴"
            return
        }
        hide()
        let keyboardImagePaste = clip.hasImagePreview && ImagePasteCompatibility.isWeChat(target?.bundleID)
        pasteCoordinator.paste(to: target, preferKeyboard: keyboardImagePaste) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                if batchCount != nil { self.state.batch.stop() }
                self.state.message = nil
            case .failure(let error): self.show(preservingTarget: true); self.state.message = error.rawValue
            }
        }
    }
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard !isRecordingShortcut else { return event }
        guard panel?.isKeyWindow == true else { return event }
        if event.keyCode == 53 {
            if state.batch.isActive { toggleBatchMode() } else { hide() }
            return nil
        }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "," { showSettings(); return nil }
        let clips = state.visible(store)
        if event.modifierFlags.contains(.command), let chars = event.charactersIgnoringModifiers, let number = Int(chars), (1...9).contains(number), clips.indices.contains(number - 1) {
            if state.batch.isActive { select(clips[number - 1]); panel.makeFirstResponder(panel.contentView) }
            else { paste(clips[number - 1]) }
            return nil
        }
        if state.batch.isActive, !(panel.firstResponder is NSTextView) {
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "a" {
                state.batch.selectAll(clips); state.message = nil; return nil
            }
            if event.keyCode == 49, event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
               let clip = clips.first(where: { $0.id == state.selectedID }) { select(clip); return nil }
        }
        if [36, 76].contains(event.keyCode) {
            if state.batch.isActive { pasteBatch(copyOnly: event.modifierFlags.contains(.shift)) }
            else if let clip = clips.first(where: { $0.id == state.selectedID }) ?? clips.first { paste(clip, copyOnly: event.modifierFlags.contains(.shift)) }
            return nil
        }
        if [123, 124].contains(event.keyCode), !(panel.firstResponder is NSTextView) {
            let index = clips.firstIndex(where: { $0.id == state.selectedID }) ?? 0
            if !clips.isEmpty { state.selectedID = clips[max(0, min(clips.count - 1, index + (event.keyCode == 124 ? 1 : -1)))].id }; return nil
        }
        if event.keyCode == 125 { panel.makeFirstResponder(panel.contentView); if state.selectedID == nil { state.selectedID = clips.first?.id }; return nil }
        if event.modifierFlags.contains(.command), event.keyCode == 51, let clip = clips.first(where: { $0.id == state.selectedID }) {
            if state.batch.isActive { state.message = "请退出多选后再删除记录。" }
            else { store.delete(clip); state.selectedID = state.visible(store).first?.id }
            return nil
        }
        return event
    }
    func showSettings() {
        hide()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 640), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "剪藏设置"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(store: store, controller: self))
            window.center(); settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func newBoard() {
        let alert = NSAlert(); alert.messageText = "新建收藏分类"; alert.informativeText = "把常用内容收在一起。最多 30 个字。"
        alert.addButton(withTitle: "创建"); alert.addButton(withTitle: "取消")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 26)); input.placeholderString = "例如：工作、灵感、常用回复"; alert.accessoryView = input
        alert.window.initialFirstResponder = input
        if alert.runModal() == .alertFirstButtonReturn, let id = store.addBoard(input.stringValue) { state.filter = .board(id) }
    }
    private func seedDemo() {
        let boardID = store.addBoard("工作灵感")!
        let samples: [(ClipKind, String, String)] = [(.text, "把灵感留住，\n让下一次表达更轻松。\n\n每一次复制，都值得被好好收藏。", "备忘录"), (.link, "https://developer.apple.com/design/", "Safari"), (.text, "你好，资料已经整理好了。\n请查收附件，有任何问题随时联系我。", "微信"), (.text, "let ideas = clipboard.collect()\nideas.keep(.inspiration)\n\n// 好想法，随手收藏。", "Xcode"), (.text, "周末的小计划\n\n☐ 去看一场展览\n☐ 整理最近的灵感\n☐ 喝一杯好咖啡", "备忘录")]
        for (kind, text, source) in samples.reversed() { store.insert(.make(kind: kind, text: text, source: source), limit: 500) }
        if let clip = store.clips.first { store.toggleStar(clip); store.toggleBoard(clip, board: Board(id: boardID, name: "工作灵感")) }
    }
}
