import SwiftUI
import ServiceManagement
import ApplicationServices

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general, appearance, shortcuts, history, privacy, about
    var id: String { rawValue }
    var title: String {
        switch self { case .general: return "通用"; case .appearance: return "外观"; case .shortcuts: return "快捷键与粘贴"; case .history: return "历史记录"; case .privacy: return "隐私"; case .about: return "关于与联系" }
    }
    var symbol: String {
        switch self { case .general: return "slider.horizontal.3"; case .appearance: return "circle.lefthalf.filled"; case .shortcuts: return "keyboard"; case .history: return "clock.arrow.circlepath"; case .privacy: return "hand.raised"; case .about: return "info.circle" }
    }
    var subtitle: String {
        switch self {
        case .general: return "让剪藏按你的习惯运行。"
        case .appearance: return "选择浅色、深色，或让外观跟随 Mac 自动变化。"
        case .shortcuts: return "设置呼出方式与卡片操作，管理直接粘贴权限。"
        case .history: return "控制记录数量、保留时间与本地存储。"
        case .privacy: return "决定哪些应用的复制内容不进入历史。"
        case .about: return "了解剪藏，联系开发者。"
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 13, weight: .semibold))
            content
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.ink.opacity(0.07)))
    }
}

private struct SettingsToggle: View {
    let title: String
    let detail: String
    @Binding var value: Bool
    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13))
                Text(detail).font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Toggle(title, isOn: $value).labelsHidden().toggleStyle(.switch).fixedSize().accessibilityLabel(title).accessibilityHint(detail)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: ClipStore
    let controller: AppController
    @ObservedObject private var preferences = Preferences.shared
    @StateObject private var login = LoginItemController()
    @StateObject private var pastePermission = PastePermissionStatus()
    @State private var category: SettingsCategory = .general
    @State private var excludedID = ""
    @State private var notice: String?
    @State private var clearConfirmation = false
    @State private var retentionConfirmation = false
    @State private var pendingRetention = HistoryRetention.forever
    @State private var pendingExpirationCount = 0
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.1" }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 190)
            Rectangle().fill(Color.ink.opacity(0.07)).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(category.title).font(.system(size: 24, weight: .semibold))
                    Text(category.subtitle).font(.system(size: 12)).foregroundColor(.secondary)
                }.padding(.horizontal, 28).padding(.top, 30).padding(.bottom, 22)
                Divider().opacity(0.5)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        page
                        if let notice { Label(notice, systemImage: "info.circle").font(.system(size: 11)).foregroundColor(.accent).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("settingsNotice") }
                    }.padding(26).frame(maxWidth: .infinity, alignment: .leading)
                }.id(category)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.frame(width: 860, height: 640).background(Color.paper).foregroundColor(.ink).tint(.accent)
        .onAppear { login.refresh(); pastePermission.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in login.refresh(); pastePermission.refresh() }
        .alert("清空未收藏的历史记录？", isPresented: $clearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空历史", role: .destructive) { store.clearHistory() }
        } message: { Text("已加入收藏或分类的内容会保留。此操作无法撤销。") }
        .alert("启用自动清理？", isPresented: $retentionConfirmation) {
            Button("取消", role: .cancel) {}
            Button("启用并清理", role: .destructive) { preferences.historyRetention = pendingRetention }
        } message: { Text("当前有 \(pendingExpirationCount) 条记录超过 \(pendingRetention.label)，启用后会删除这些记录。收藏和分类中的内容会保留。") }
        .alert("存储遇到问题", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("好") { store.error = nil } } message: { Text(store.error ?? "") }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSImage.clipNestIcon).resizable().scaledToFit().frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 3) { Text("剪藏").font(.system(size: 21, weight: .semibold)); Text("偏好设置").font(.system(size: 10)).foregroundColor(.secondary) }
            }.padding(.horizontal, 20).padding(.top, 30).padding(.bottom, 28)
            VStack(spacing: 5) {
                ForEach(SettingsCategory.allCases) { item in
                    Button { category = item; notice = nil } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.symbol).font(.system(size: 15)).frame(width: 20)
                            Text(item.title).font(.system(size: 12, weight: category == item ? .semibold : .regular))
                            Spacer(minLength: 0)
                        }.padding(.horizontal, 12).frame(height: 39)
                            .foregroundColor(category == item ? .accent : .ink.opacity(0.7))
                            .background(category == item ? Color.accent.opacity(0.12) : .clear).cornerRadius(9).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("settings-\(item.rawValue)")
                }
            }.padding(.horizontal, 12)
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Text("剪藏 \(version)").font(.system(size: 11, weight: .medium))
                Label("本地保存，无需账号", systemImage: "internaldrive").font(.system(size: 10)).foregroundColor(.secondary)
            }.padding(22)
        }.background(Color.chrome)
    }
    @ViewBuilder private var page: some View {
        switch category {
        case .general: general
        case .appearance: appearance
        case .shortcuts: shortcuts
        case .history: history
        case .privacy: privacy
        case .about: about
        }
    }
    private var general: some View {
        VStack(spacing: 16) {
            SettingsCard("启动与运行") {
                SettingsToggle(title: "登录 Mac 时自动启动", detail: login.description, value: Binding(get: { login.requested }, set: { login.setEnabled($0) }))
                if let error = login.error { Text(error).font(.system(size: 11)).foregroundColor(.accent) }
                if login.state == .pendingApproval || login.state == .unavailable { Button("打开系统登录项设置…") { SMAppService.openSystemSettingsLoginItems() } }
            }
            SettingsCard("菜单栏") {
                SettingsToggle(title: "显示菜单栏图标", detail: "通过菜单栏随时打开剪藏、暂停记录或退出。", value: Binding(get: { preferences.showMenuBarIcon }, set: { notice = controller.setMenuBarVisible($0) }))
                Text("隐藏图标后，按 \(preferences.shortcut.display) 呼出面板；也可在 Finder 中重新双击剪藏。").font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private var appearance: some View {
        VStack(spacing: 16) {
            SettingsCard("应用外观") {
                HStack(spacing: 12) {
                    ForEach(ThemeMode.allCases) { mode in
                        Button { preferences.theme = mode } label: {
                            VStack(spacing: 11) {
                                themePreview(mode)
                                HStack(spacing: 5) {
                                    Image(systemName: mode.symbol)
                                    Text(mode.label)
                                    Spacer(minLength: 0)
                                    Image(systemName: preferences.theme == mode ? "checkmark.circle.fill" : "circle").foregroundColor(preferences.theme == mode ? .accent : .secondary)
                                }.font(.system(size: 11, weight: .medium))
                            }.padding(12).background(Color.paper).cornerRadius(10)
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(preferences.theme == mode ? Color.accent : Color.ink.opacity(0.10), lineWidth: preferences.theme == mode ? 2 : 1))
                        }.buttonStyle(.plain).accessibilityLabel(mode.label).accessibilityIdentifier("theme-\(mode.rawValue)")
                    }
                }
                Text(preferences.theme == .system ? "已跟随系统：macOS 的浅色与深色外观变化时，剪藏会自动切换。" : "已选择\(preferences.theme.label)外观，面板和设置窗口会立即更新。").font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            SettingsCard("卡片配色") {
                Label("来源 App 的专属色条会保留", systemImage: "paintpalette").font(.system(size: 13))
                Text("卡片正文、搜索框和窗口背景会随外观调整；图标和顶部色条帮助你辨认来源。").font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func themePreview(_ mode: ThemeMode) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(mode == .dark ? Color(red: 0.12, green: 0.13, blue: 0.15) : Color(red: 0.95, green: 0.94, blue: 0.91))
            if mode == .system { HStack(spacing: 0) { Color.clear; Color(red: 0.12, green: 0.13, blue: 0.15) }.clipShape(RoundedRectangle(cornerRadius: 6)) }
            VStack(spacing: 8) {
                HStack(spacing: 3) { ForEach(0..<3, id: \.self) { _ in Circle().fill(Color.gray.opacity(0.45)).frame(width: 4, height: 4) }; Spacer() }
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in
                        VStack(spacing: 0) { Color.orange.opacity(index == 1 ? 0.5 : 0.85).frame(height: 9); (mode == .dark || (mode == .system && index > 0) ? Color.white.opacity(0.13) : Color.white).frame(height: 27) }.cornerRadius(3)
                    }
                }
            }.padding(9)
        }.frame(height: 72).accessibilityHidden(true)
    }
    private var shortcuts: some View {
        VStack(spacing: 16) {
            SettingsCard("呼出面板") {
                HStack { Text("全局快捷键").font(.system(size: 13)); Spacer(); ShortcutRecorder(shortcut: preferences.shortcut, controller: controller, report: { notice = $0 }).frame(width: 145, height: 30); Button("恢复默认") { notice = controller.finishShortcutRecording(.defaultShortcut) ?? "已恢复默认快捷键。" } }
                Text("点击快捷键按钮后按新组合键，按 Esc 取消。设置会立即保存。").font(.system(size: 11)).foregroundColor(.secondary)
            }
            SettingsCard("卡片交互") {
                SettingsToggle(title: "双击卡片直接粘贴", detail: "默认关闭以减少误触。单击只选择，回车或卡片底部箭头执行粘贴。", value: $preferences.doubleClickToPaste)
                Divider()
                HStack { Text("仅复制到剪贴板"); Spacer(); Text("⇧ ↩").font(.system(.body, design: .monospaced)) }.font(.system(size: 12))
                HStack { Text("快速粘贴前九条"); Spacer(); Text("⌘1–9").font(.system(.body, design: .monospaced)) }.font(.system(size: 12))
            }
            pastePermissions
        }
    }
    private var pastePermissions: some View {
        SettingsCard("直接粘贴权限") {
            let ready = pastePermission.accessibility && pastePermission.eventPosting
            Label(ready ? "当前版本可以直接粘贴" : (pastePermission.accessibility ? "按键权限尚未生效" : "当前版本尚未授权"), systemImage: ready ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.system(size: 12, weight: .medium)).foregroundColor(ready ? .green : .accent)
            Text(pastePermission.accessibility && !pastePermission.eventPosting ? "系统已允许辅助功能，但当前进程的按键权限尚未生效。授权后请按 ⌘Q 完全退出，再重新打开剪藏。" : pastePermission.explanation).font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("打开辅助功能设置…") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }
                Button("重新检查") { pastePermission.refresh(); notice = pastePermission.accessibility && pastePermission.eventPosting ? "辅助功能和粘贴按键权限均已生效。" : "请检查当前应用的授权状态；授权后完整退出并重新打开剪藏。" }
            }
            DisclosureGroup("当前运行位置") {
                VStack(alignment: .leading, spacing: 9) { Text(pastePermission.applicationURL.path).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true); Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([pastePermission.applicationURL]) } }.padding(.top, 8)
            }.font(.system(size: 11)).foregroundColor(.secondary)
        }
    }
    private var history: some View {
        VStack(spacing: 16) {
            SettingsCard("记录行为") {
                SettingsToggle(title: "暂停记录剪贴板", detail: "暂停期间的新复制内容不会进入历史。", value: $preferences.paused)
                Divider()
                HStack { Text("历史数量上限").font(.system(size: 13)); Spacer(); Picker("历史数量上限", selection: $preferences.limit) { ForEach([100, 500, 1000, 2000], id: \.self) { Text("\($0) 条").tag($0) } }.labelsHidden().frame(width: 150) }.onChange(of: preferences.limit) { store.prune(limit: $0) }
            }
            SettingsCard("自动清理") {
                HStack { Text("历史保留时间").font(.system(size: 13)); Spacer(); Picker("历史保留时间", selection: Binding(get: { preferences.historyRetention }, set: requestRetention)) { ForEach(HistoryRetention.allCases) { period in Text(period.label).tag(period) } }.labelsHidden().frame(width: 170).accessibilityIdentifier("historyRetention") }
                Text("按最后复制时间计算。应用启动、运行期间每小时、Mac 唤醒后会检查过期记录。").font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                Label("收藏和分类中的内容始终保留", systemImage: "star").font(.system(size: 11)).foregroundColor(.accent)
            }
            SettingsCard("本地数据") {
                Text("\(store.clips.count) 条记录 · \(store.boards.count) 个分类").font(.system(size: 13))
                Text("图片单条不超过 20 MB，文本不超过 1 MB。普通文件保存位置，单张图片文件额外缓存图片内容。").font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack { Button("在 Finder 中显示数据库") { NSWorkspace.shared.activateFileViewerSelecting([store.url]) }; Spacer(); Button("清空未收藏历史…", role: .destructive) { clearConfirmation = true } }
                Text(store.url.deletingLastPathComponent().path).font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func requestRetention(_ retention: HistoryRetention) {
        guard retention != preferences.historyRetention else { return }
        let count = store.expiredCount(retention: retention)
        if count > 0 { pendingRetention = retention; pendingExpirationCount = count; retentionConfirmation = true }
        else { preferences.historyRetention = retention }
    }
    private var privacy: some View {
        VStack(spacing: 16) {
            SettingsCard("排除应用") {
                Text("以下应用复制的内容不会被记录。").font(.system(size: 11)).foregroundColor(.secondary)
                if preferences.excluded.isEmpty { Text("尚未排除任何应用").font(.system(size: 12)).foregroundColor(.secondary).padding(.vertical, 12) }
                ForEach(preferences.excluded, id: \.self) { id in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) { Text(applicationName(for: id)).font(.system(size: 12)); Text(id).font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary).lineLimit(1) }
                        Spacer()
                        Button { preferences.excluded.removeAll { $0 == id } } label: { Image(systemName: "minus.circle").foregroundColor(.secondary) }.buttonStyle(.plain).help("从排除列表移除")
                    }.padding(.vertical, 5)
                    if id != preferences.excluded.last { Divider() }
                }
                Button("选择要排除的应用…") {
                    let picker = NSOpenPanel(); picker.canChooseDirectories = false; picker.allowedContentTypes = [.application]; picker.directoryURL = URL(fileURLWithPath: "/Applications")
                    if picker.runModal() == .OK, let url = picker.url, let id = Bundle(url: url)?.bundleIdentifier { addExcluded(id) }
                }
                DisclosureGroup("按 Bundle ID 添加") { HStack { TextField("例如 com.apple.Notes", text: $excludedID).textFieldStyle(.roundedBorder); Button("添加") { addExcluded(excludedID) } }.padding(.top, 8) }.font(.system(size: 11)).foregroundColor(.secondary)
            }
            SettingsCard("隐私与存储说明") {
                Text("自动跳过标记为机密、临时或自动生成的内容。未加标记的密码无法自动识别，敏感操作前可暂停记录。排除应用不会删除已有记录。").font(.system(size: 11)).foregroundColor(.secondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                Text("历史仅保存在本机 SQLite 中，未加密。备份前请退出剪藏并复制整个数据目录。").font(.system(size: 11)).foregroundColor(.secondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func applicationName(for id: String) -> String { NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.deletingPathExtension().lastPathComponent ?? id }
    private func addExcluded(_ value: String) {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !preferences.excluded.contains(value) else { return }
        preferences.excluded.append(value); excludedID = ""
    }
    private var about: some View {
        VStack(spacing: 16) {
            SettingsCard("关于剪藏") {
                HStack(spacing: 15) {
                    Image(nsImage: NSImage.clipNestIcon).resizable().scaledToFit().frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 6) { Text("剪藏 · ClipNest").font(.system(size: 20, weight: .semibold)); Text("版本 \(version)").font(.system(size: 12)).foregroundColor(.secondary); Text("随手复制，好好收藏。").font(.system(size: 12)).foregroundColor(.secondary) }
                }
                Divider()
                HStack { Text("开发者").foregroundColor(.secondary); Spacer(); Text("BrittneyKarbows").textSelection(.enabled) }.font(.system(size: 12))
            }
            SettingsCard("联系我们") {
                VStack(alignment: .leading, spacing: 14) {
                    Label { Link("BrittneyKarbows@gmail.com", destination: URL(string: "mailto:BrittneyKarbows@gmail.com")!).textSelection(.enabled) } icon: { Image(systemName: "envelope") }
                    Label { Link("github.com/BrittneyKarbows", destination: URL(string: "https://github.com/BrittneyKarbows")!) } icon: { Image(systemName: "link") }
                }.font(.system(size: 13))
                Text("欢迎反馈问题和建议。反馈时可附上软件版本与复现步骤。").font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text("© 2026 BrittneyKarbows").font(.system(size: 10)).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center).padding(.top, 5)
        }
    }
}

// Native button captures key events before menu equivalents, and always restores
// registration when cancelled, when its tab disappears, or when focus is lost.
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: KeyboardShortcut
    let controller: AppController
    let report: (String?) -> Void
    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.controller = controller; button.report = report
        button.title = shortcut.display
        return button
    }
    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.report = report
        if !button.recording { button.title = shortcut.display }
    }
    static func dismantleNSView(_ button: ShortcutRecorderButton, coordinator: ()) { button.cancel() }
}

final class ShortcutRecorderButton: NSButton {
    weak var controller: AppController?
    var report: ((String?) -> Void)?
    private(set) var recording = false
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded; setButtonType(.momentaryPushIn)
        font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        target = self; action = #selector(begin)
        setAccessibilityLabel("修改呼出面板快捷键")
        toolTip = "点击后按新的组合键，Esc 取消"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func begin() {
        guard !recording else { cancel(); return }
        recording = true; title = "请按组合键…"; report?(nil)
        controller?.beginShortcutRecording()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.recording else { return event }
            if event.type != .keyDown { self.cancel(); return event }
            if event.keyCode == 53 { self.cancel(); return nil }
            if event.isARepeat { return nil }
            let candidate = KeyboardShortcut(event: event)
            if let error = candidate.validationError { self.report?(error); return nil }
            self.cleanup()
            let error = self.controller?.finishShortcutRecording(candidate)
            self.title = Preferences.shared.shortcut.display
            self.report?(error ?? "快捷键已保存：\(candidate.display)")
            return nil
        }
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification, NSApplication.didResignActiveNotification] {
            let observer = NotificationCenter.default.addObserver(forName: name, object: name == NSApplication.didResignActiveNotification ? NSApp : window, queue: .main) { [weak self] _ in self?.cancel() }
            observers.append(observer)
        }
    }
    private func cleanup() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers.removeAll()
    }
    func cancel() {
        guard recording else { return }
        cleanup(); controller?.finishShortcutRecording(nil)
        title = Preferences.shared.shortcut.display
        report?("已取消，快捷键未更改。")
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) }; observers.forEach { NotificationCenter.default.removeObserver($0) } }
}
