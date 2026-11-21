import AppKit
import CryptoKit
import ServiceManagement

enum ThemeMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { switch self { case .system: return "跟随系统"; case .light: return "浅色"; case .dark: return "深色" } }
    var symbol: String { switch self { case .system: return "circle.lefthalf.filled"; case .light: return "sun.max"; case .dark: return "moon" } }
    var appearance: NSAppearance? { switch self { case .system: return nil; case .light: return NSAppearance(named: .aqua); case .dark: return NSAppearance(named: .darkAqua) } }
}

enum HistoryRetention: String, CaseIterable, Identifiable {
    case forever, week, month, threeMonths, sixMonths, year
    var id: String { rawValue }
    var label: String { switch self { case .forever: return "永不自动删除"; case .week: return "7 天"; case .month: return "1 个月"; case .threeMonths: return "3 个月"; case .sixMonths: return "6 个月"; case .year: return "1 年" } }
    func cutoff(relativeTo now: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .forever: return nil
        case .week: return calendar.date(byAdding: .day, value: -7, to: now)
        case .month: return calendar.date(byAdding: .month, value: -1, to: now)
        case .threeMonths: return calendar.date(byAdding: .month, value: -3, to: now)
        case .sixMonths: return calendar.date(byAdding: .month, value: -6, to: now)
        case .year: return calendar.date(byAdding: .year, value: -1, to: now)
        }
    }
}

enum ClipKind: String, Codable, CaseIterable {
    case text, link, image, files
    var label: String { switch self { case .text: return "文本"; case .link: return "链接"; case .image: return "图片"; case .files: return "文件" } }
    var symbol: String { switch self { case .text: return "text.alignleft"; case .link: return "link"; case .image: return "photo"; case .files: return "doc.on.doc" } }
}

enum LoginItemState { case disabled, enabled, pendingApproval, unavailable }

struct LoginItemBackend {
    var state: () -> LoginItemState
    var register: () throws -> Void
    var unregister: () throws -> Void
    static let system = LoginItemBackend(state: {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .pendingApproval
        case .notRegistered: return .disabled
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }, register: { try SMAppService.mainApp.register() }, unregister: { try SMAppService.mainApp.unregister() })
}

final class LoginItemController: ObservableObject {
    @Published private(set) var state: LoginItemState
    @Published private(set) var error: String?
    private let backend: LoginItemBackend
    var requested: Bool { state == .enabled || state == .pendingApproval }
    var description: String {
        switch state {
        case .enabled: return "已启用，下次登录 Mac 时自动启动。"
        case .pendingApproval: return "等待系统批准：请在系统设置的登录项中允许剪藏。"
        case .disabled: return "关闭时，需要手动打开剪藏。"
        case .unavailable: return "系统暂时无法找到登录服务，请先将剪藏移入应用程序文件夹。"
        }
    }
    init(backend: LoginItemBackend = .system) { self.backend = backend; state = backend.state() }
    func refresh() { state = backend.state() }
    func setEnabled(_ enabled: Bool) {
        error = nil
        do {
            if enabled { if !requested { try backend.register() } }
            else if requested { try backend.unregister() }
        } catch { self.error = "登录启动设置失败：\(error.localizedDescription)" }
        refresh()
    }
}

struct Clip: Identifiable {
    let id: String
    let kind: ClipKind
    let text: String
    let data: Data?
    let source: String
    let bundleID: String
    let created: Date
    var updated: Date
    var starred: Bool
    var boards: Set<String>
    var hasImagePreview: Bool { data != nil && (kind == .image || kind == .files) }
    var kindLabel: String { kind == .files && hasImagePreview ? "图片文件" : kind.label }
    var title: String {
        if kind == .image { return "复制的图片" }
        if kind == .files { return text.components(separatedBy: "\n").compactMap { URL(string: $0)?.lastPathComponent }.joined(separator: "、") }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func make(kind: ClipKind, text: String, data: Data? = nil, source: String, bundleID: String = "") -> Clip {
        let digest = SHA256.hash(data: Data(kind.rawValue.utf8) + (data ?? Data(text.utf8)))
        let id = digest.map { String(format: "%02x", $0) }.joined()
        return Clip(id: id, kind: kind, text: text, data: data, source: source, bundleID: bundleID, created: Date(), updated: Date(), starred: false, boards: [])
    }
}

struct Board: Identifiable { let id: String; let name: String }

enum ClipFilter: Hashable { case history, starred, board(String), kind(ClipKind) }

enum PanelDismissalPolicy {
    static func shouldDismiss(visible: Bool, panelFrame: CGRect, statusFrame: CGRect?, click: CGPoint, eventTime: TimeInterval, shownAt: TimeInterval) -> Bool {
        guard visible, eventTime >= shownAt + 0.2 else { return false }
        guard !panelFrame.insetBy(dx: -4, dy: -4).contains(click) else { return false }
        if let statusFrame, statusFrame.insetBy(dx: -3, dy: -3).contains(click) { return false }
        return true
    }
}

final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let defaults: UserDefaults
    @Published var paused: Bool { didSet { defaults.set(paused, forKey: "paused") } }
    @Published var limit: Int { didSet { defaults.set(limit, forKey: "limit") } }
    @Published var excluded: [String] { didSet { defaults.set(excluded, forKey: "excluded") } }
    @Published var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon") } }
    @Published var doubleClickToPaste: Bool { didSet { defaults.set(doubleClickToPaste, forKey: "doubleClickToPaste") } }
    @Published var theme: ThemeMode { didSet { defaults.set(theme.rawValue, forKey: "theme") } }
    @Published var historyRetention: HistoryRetention { didSet { defaults.set(historyRetention.rawValue, forKey: "historyRetention") } }
    @Published private(set) var shortcut: KeyboardShortcut
    func saveShortcut(_ value: KeyboardShortcut) {
        guard value.validationError == nil, let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: "panelShortcut")
        shortcut = value
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        paused = defaults.bool(forKey: "paused")
        limit = defaults.object(forKey: "limit") as? Int ?? 500
        excluded = defaults.stringArray(forKey: "excluded") ?? ["com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop", "com.apple.keychainaccess"]
        showMenuBarIcon = defaults.object(forKey: "showMenuBarIcon") as? Bool ?? true
        doubleClickToPaste = defaults.object(forKey: "doubleClickToPaste") as? Bool ?? false
        theme = ThemeMode(rawValue: defaults.string(forKey: "theme") ?? "") ?? .system
        historyRetention = HistoryRetention(rawValue: defaults.string(forKey: "historyRetention") ?? "") ?? .forever
        if let data = defaults.data(forKey: "panelShortcut"), let saved = try? JSONDecoder().decode(KeyboardShortcut.self, from: data), saved.validationError == nil { shortcut = saved }
        else { shortcut = .defaultShortcut }
    }
}
