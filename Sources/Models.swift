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

enum AccentPalette: String, CaseIterable, Identifiable {
    case monochrome, blue, purple, green, rose, teal
    var id: String { rawValue }
    var label: String {
        switch self {
        case .monochrome: return "黑白"
        case .blue: return "蓝色"
        case .purple: return "紫色"
        case .green: return "绿色"
        case .rose: return "玫红"
        case .teal: return "青色"
        }
    }
    func color(isDark: Bool) -> NSColor {
        let rgb: (CGFloat, CGFloat, CGFloat)
        switch self {
        case .monochrome: rgb = isDark ? (0.93, 0.93, 0.93) : (0.12, 0.12, 0.12)
        case .blue: rgb = isDark ? (0.42, 0.68, 1.0) : (0.13, 0.39, 0.88)
        case .purple: rgb = isDark ? (0.73, 0.58, 1.0) : (0.48, 0.25, 0.78)
        case .green: rgb = isDark ? (0.40, 0.80, 0.57) : (0.10, 0.45, 0.30)
        case .rose: rgb = isDark ? (1.0, 0.55, 0.71) : (0.72, 0.22, 0.40)
        case .teal: rgb = isDark ? (0.35, 0.79, 0.83) : (0.0, 0.44, 0.49)
        }
        return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
    }
    var adaptiveColor: NSColor {
        NSColor(name: nil) { appearance in
            self.color(isDark: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        }
    }
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

enum BatchPasteError: LocalizedError, Equatable {
    case noSelection, missingItem, unsupportedItem, emptyItem, tooLarge
    var errorDescription: String? {
        switch self {
        case .noSelection: return "请先勾选要一起粘贴的文字或链接。"
        case .missingItem: return "部分所选记录已不存在，请清空选择后重新勾选。"
        case .unsupportedItem: return "批量拼接仅支持文字和链接，不能包含图片或文件。"
        case .emptyItem: return "所选内容中有空白记录，请重新选择。"
        case .tooLarge: return "拼接结果超过 1 MB，请减少选择的记录。"
        }
    }
}

struct BatchPasteSelection {
    static let byteLimit = 1024 * 1024
    private(set) var isActive = false
    private(set) var orderedIDs: [String] = []
    static func canSelect(_ clip: Clip) -> Bool {
        (clip.kind == .text || clip.kind == .link) && !clip.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    mutating func start() { isActive = true; orderedIDs = [] }
    mutating func stop() { isActive = false; orderedIDs = [] }
    mutating func clear() { orderedIDs = [] }
    mutating func toggle(_ clip: Clip) {
        guard isActive, Self.canSelect(clip) else { return }
        if let index = orderedIDs.firstIndex(of: clip.id) { orderedIDs.remove(at: index) }
        else { orderedIDs.append(clip.id) }
    }
    mutating func selectAll(_ clips: [Clip]) {
        guard isActive else { return }
        for clip in clips where Self.canSelect(clip) && !orderedIDs.contains(clip.id) { orderedIDs.append(clip.id) }
    }
    func order(for id: String) -> Int? { orderedIDs.firstIndex(of: id).map { $0 + 1 } }
    func joinedText(from clips: [Clip]) throws -> String {
        guard !orderedIDs.isEmpty else { throw BatchPasteError.noSelection }
        var byID: [String: Clip] = [:]
        for clip in clips { byID[clip.id] = clip }
        var parts: [String] = []
        var bytes = 0
        for id in orderedIDs {
            guard let clip = byID[id] else { throw BatchPasteError.missingItem }
            guard clip.kind == .text || clip.kind == .link else { throw BatchPasteError.unsupportedItem }
            let text = clip.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw BatchPasteError.emptyItem }
            bytes += text.utf8.count + (parts.isEmpty ? 0 : 1)
            guard bytes <= Self.byteLimit else { throw BatchPasteError.tooLarge }
            parts.append(text)
        }
        return parts.joined(separator: " ")
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
    @Published var accentPalette: AccentPalette { didSet { defaults.set(accentPalette.rawValue, forKey: "accentPalette") } }
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
        accentPalette = AccentPalette(rawValue: defaults.string(forKey: "accentPalette") ?? "") ?? .monochrome
        historyRetention = HistoryRetention(rawValue: defaults.string(forKey: "historyRetention") ?? "") ?? .forever
        if let data = defaults.data(forKey: "panelShortcut"), let saved = try? JSONDecoder().decode(KeyboardShortcut.self, from: data), saved.validationError == nil { shortcut = saved }
        else { shortcut = .defaultShortcut }
    }
}
