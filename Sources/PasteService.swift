import AppKit
import ApplicationServices

struct PasteDestination {
    let pid: pid_t
    let name: String
    var focusedElement: AXUIElement? = nil
    var bundleID: String = ""
}

enum PasteMenuResult { case performed, disabled, unavailable, failed }
enum DirectPasteError: String, Error {
    case permission = "当前运行的剪藏尚未获得辅助功能权限。请在设置中核对运行位置，并为这一份应用授权。内容已复制，可手动按 ⌘V。"
    case noTarget = "未找到粘贴目标。请先点击目标应用的输入框，再用快捷键打开剪藏。内容已复制。"
    case targetClosed = "目标应用已退出。内容已复制，请重新打开目标应用后粘贴。"
    case activation = "目标窗口尚未就绪，未发送粘贴。内容已复制，请点击目标输入框后重试。"
    case focusChanged = "前台应用发生变化，已取消本次直接粘贴。内容仍在剪贴板中。"
    case modifiers = "请松开快捷键后重试。内容已复制，未发送额外按键。"
    case disabled = "目标应用当前不允许粘贴。请先点击可编辑的输入框，再重新呼出剪藏。"
    case events = "系统仍限制当前版本发送粘贴按键。请在设置中核对授权；内容已复制，可手动按 ⌘V。"
    case command = "目标应用未确认粘贴操作，未重复发送按键。内容已复制，请点击目标输入框后重试。"
}

protocol PasteEnvironment {
    var trusted: Bool { get }
    var mayPostEvents: Bool { get }
    var ownPID: pid_t { get }
    var frontmostPID: pid_t? { get }
    var modifiersHeld: Bool { get }
    func isRunning(_ target: PasteDestination) -> Bool
    func activate(_ target: PasteDestination) -> Bool
    func restoreFocus(_ target: PasteDestination)
    func pressPasteMenu(_ target: PasteDestination) -> PasteMenuResult
    func postPaste(_ target: PasteDestination) -> Bool
}

// Wait for actual activation and modifier release rather than guessing a delay.
// One request sends at most one paste, and cancels if the user switches elsewhere.
final class PasteCoordinator {
    typealias Scheduler = (TimeInterval, @escaping () -> Void) -> Void
    private let environment: PasteEnvironment
    private let schedule: Scheduler
    private let now: () -> TimeInterval
    private var request = UUID()
    private(set) var isBusy = false
    init(environment: PasteEnvironment = MacPasteEnvironment(), schedule: @escaping Scheduler = { delay, action in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action) }, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.environment = environment; self.schedule = schedule; self.now = now
    }
    func cancel() { request = UUID(); isBusy = false }
    func paste(to target: PasteDestination?, preferKeyboard: Bool = false, completion: @escaping (Result<Void, DirectPasteError>) -> Void) {
        cancel()
        guard environment.trusted else { completion(.failure(.permission)); return }
        guard let target, target.pid != environment.ownPID else { completion(.failure(.noTarget)); return }
        guard environment.isRunning(target) else { completion(.failure(.targetClosed)); return }
        guard environment.activate(target) else { completion(.failure(.activation)); return }
        let id = request; isBusy = true
        let deadline = now() + 1.8
        func finish(_ result: Result<Void, DirectPasteError>) {
            guard self.request == id else { return }
            self.isBusy = false; self.request = UUID(); completion(result)
        }
        func check(stable: Bool) {
            guard self.request == id else { return }
            guard self.environment.trusted else { finish(.failure(.permission)); return }
            guard self.environment.isRunning(target) else { finish(.failure(.targetClosed)); return }
            let front = self.environment.frontmostPID
            if let front, front != target.pid && front != self.environment.ownPID { finish(.failure(.focusChanged)); return }
            let ready = front == target.pid
            guard ready, stable, !self.environment.modifiersHeld else {
                if self.now() >= deadline { finish(.failure(ready && self.environment.modifiersHeld ? .modifiers : .activation)); return }
                self.schedule(0.05) { check(stable: ready) }; return
            }
            self.environment.restoreFocus(target)
            guard self.environment.frontmostPID == target.pid else { finish(.failure(.focusChanged)); return }
            // Some custom chat editors handle image paste on Cmd-V rather than
            // through the standard AppKit Paste menu. Never send both routes.
            if preferKeyboard && self.environment.mayPostEvents {
                finish(self.environment.postPaste(target) ? .success(()) : .failure(.events)); return
            }
            switch self.environment.pressPasteMenu(target) {
            case .performed: finish(.success(()))
            case .disabled: finish(.failure(.disabled))
            case .failed: finish(.failure(.command))
            case .unavailable:
                guard self.environment.mayPostEvents, self.environment.postPaste(target) else { finish(.failure(.events)); return }
                finish(.success(()))
            }
        }
        schedule(0.05) { check(stable: false) }
    }
}

final class MacPasteEnvironment: PasteEnvironment {
    var trusted: Bool { AXIsProcessTrusted() }
    var mayPostEvents: Bool { CGPreflightPostEventAccess() }
    var ownPID: pid_t { ProcessInfo.processInfo.processIdentifier }
    var frontmostPID: pid_t? { NSWorkspace.shared.frontmostApplication?.processIdentifier }
    var modifiersHeld: Bool { !NSEvent.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty }
    func isRunning(_ target: PasteDestination) -> Bool { NSRunningApplication(processIdentifier: target.pid).map { !$0.isTerminated } ?? false }
    func activate(_ target: PasteDestination) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: target.pid) else { return false }
        if #available(macOS 14.0, *) { NSApp.yieldActivation(to: app); return app.activate(options: []) }
        return app.activate(options: [.activateIgnoringOtherApps])
    }
    func restoreFocus(_ target: PasteDestination) {
        guard let element = target.focusedElement else { return }
        AXUIElementSetMessagingTimeout(element, 0.2)
        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(element, kAXFocusedAttribute as CFString, &settable) == .success, settable.boolValue {
            AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
    }
    static func destination(for app: NSRunningApplication) -> PasteDestination {
        var focused: CFTypeRef?
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.2)
        if AXIsProcessTrusted() { AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &focused) }
        let focus = focused.flatMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
        return PasteDestination(pid: app.processIdentifier, name: app.localizedName ?? "目标应用", focusedElement: focus, bundleID: app.bundleIdentifier ?? "")
    }
    func pressPasteMenu(_ target: PasteDestination) -> PasteMenuResult {
        let app = AXUIElementCreateApplication(target.pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
        }
        guard let value = attribute(app, kAXMenuBarAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return .unavailable }
        let menuBar = value as! AXUIElement
        var remaining = 160
        func find(_ element: AXUIElement, depth: Int) -> AXUIElement? {
            guard depth <= 4, remaining > 0 else { return nil }; remaining -= 1
            let title = (attribute(element, kAXTitleAttribute) as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let character = (attribute(element, kAXMenuItemCmdCharAttribute) as? String ?? "").lowercased()
            let modifiers = (attribute(element, kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue
            let role = attribute(element, kAXRoleAttribute) as? String
            if role == kAXMenuItemRole && (["paste", "粘贴", "貼上", "ペースト", "붙여넣기"].contains(title) || (character == "v" && modifiers == 0)) { return element }
            let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
            for child in children.prefix(50) { if let found = find(child, depth: depth + 1) { return found } }
            return nil
        }
        let roots = attribute(menuBar, kAXChildrenAttribute) as? [AXUIElement] ?? []
        // Inspect Edit first, then fall back to other menus without opening them.
        let editNames = ["edit", "编辑", "編輯", "編集", "편집"]
        let ordered = roots.sorted { lhs, rhs in
            let left = (attribute(lhs, kAXTitleAttribute) as? String ?? "").lowercased()
            let right = (attribute(rhs, kAXTitleAttribute) as? String ?? "").lowercased()
            return editNames.contains(left) && !editNames.contains(right)
        }
        for root in ordered {
            guard let item = find(root, depth: 0) else { continue }
            if (attribute(item, kAXEnabledAttribute) as? NSNumber)?.boolValue == false { return .disabled }
            return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success ? .performed : .failed
        }
        return .unavailable
    }
    func postPaste(_ target: PasteDestination) -> Bool {
        guard frontmostPID == target.pid, mayPostEvents,
              let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return false }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.postToPid(target.pid); up.postToPid(target.pid)
        return true
    }
}

final class PastePermissionStatus: ObservableObject {
    @Published private(set) var accessibility = false
    @Published private(set) var eventPosting = false
    let applicationURL = Bundle.main.bundleURL
    var explanation: String {
        accessibility ? "系统已允许当前运行版本使用辅助功能。" : "系统尚未授权当前运行版本。若列表中已勾选剪藏，可能对应旧版或另一位置的副本；请移除旧条目后重新添加下方位置的应用。"
    }
    init() { refresh() }
    func refresh() { accessibility = AXIsProcessTrusted(); eventPosting = CGPreflightPostEventAccess() }
}
