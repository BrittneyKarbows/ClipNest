import AppKit
import Carbon

struct KeyboardShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    static let defaultShortcut = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey))
    static let modifierMask = UInt32(cmdKey | controlKey | optionKey | shiftKey)
    // Physical macOS keys remain stable when switching between Chinese and English input.
    static let keys: [UInt32: String] = [
        0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",
        18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"−",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",49:"空格",50:"`",
        64:"F17",65:"小数点",67:"×",69:"+",75:"÷",78:"−",79:"F18",80:"F19",81:"=",82:"0",83:"1",84:"2",85:"3",86:"4",87:"5",88:"6",89:"7",91:"8",92:"9",96:"F5",97:"F6",98:"F7",99:"F3",100:"F8",101:"F9",103:"F11",105:"F13",106:"F16",107:"F14",109:"F10",111:"F12",113:"F15",115:"Home",116:"Page Up",118:"F4",119:"End",120:"F2",121:"Page Down",122:"F1",123:"←",124:"→",125:"↓",126:"↑"
    ]
    var display: String {
        var text = ""
        for (flag, symbol) in [(controlKey,"⌃"),(optionKey,"⌥"),(shiftKey,"⇧"),(cmdKey,"⌘")] { if modifiers & UInt32(flag) != 0 { text += symbol } }
        return text + (Self.keys[keyCode] ?? "?")
    }
    var validationError: String? {
        guard Self.keys[keyCode] != nil, modifiers & ~Self.modifierMask == 0 else { return "不支持这个按键，请换一组快捷键。" }
        guard modifiers & UInt32(cmdKey | controlKey | optionKey) != 0 else { return "请至少搭配 Command、Control 或 Option 中的一个修饰键。" }
        if modifiers == UInt32(cmdKey), [0,6,7,8,9,12,13,4,46,43,18,19,20,21,23,22,26,28,25,29].contains(keyCode) { return "这组快捷键用于常规编辑或窗口操作，请换一组。" }
        if (keyCode == 49 && (modifiers == UInt32(cmdKey) || modifiers == UInt32(controlKey))) || (keyCode == 12 && (modifiers == UInt32(cmdKey | controlKey) || modifiers == UInt32(cmdKey | shiftKey))) || (modifiers == UInt32(controlKey) && (123...126).contains(keyCode)) { return "这组快捷键用于系统操作，请换一组。" }
        return nil
    }
    init(keyCode: UInt32, modifiers: UInt32) { self.keyCode = keyCode; self.modifiers = modifiers }
    init(event: NSEvent) {
        keyCode = UInt32(event.keyCode)
        var value: UInt32 = 0
        for (flag, carbon) in [(NSEvent.ModifierFlags.command, cmdKey), (.control, controlKey), (.option, optionKey), (.shift, shiftKey)] { if event.modifierFlags.contains(flag) { value |= UInt32(carbon) } }
        modifiers = value
    }
}

struct HotKeyPressGate {
    private var held = false
    mutating func press() -> Bool { guard !held else { return false }; held = true; return true }
    mutating func release() { held = false }
}

final class HotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var eventID: UInt32 = 0
    private static var nextID: UInt32 = 1
    private var pressGate = HotKeyPressGate()
    private(set) var current: KeyboardShortcut?
    var isRegistered: Bool { reference != nil }
    var onPress: (() -> Void)?
    @discardableResult func register(_ shortcut: KeyboardShortcut) -> Bool {
        guard shortcut.validationError == nil else { return false }
        if current == shortcut && isRegistered { return true }
        if handler == nil {
            var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)), EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue()
                var id = EventHotKeyID()
                guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr, id.signature == OSType(0x434C504E), id.id == hotKey.eventID else { return OSStatus(eventNotHandledErr) }
                if GetEventKind(event) == UInt32(kEventHotKeyReleased) { hotKey.pressGate.release(); return noErr }
                guard hotKey.pressGate.press() else { return noErr }
                DispatchQueue.main.async { [weak hotKey] in hotKey?.onPress?() }
                return noErr
            }, 2, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { return false }
        }
        let id = Self.nextID; Self.nextID &+= 1
        var candidate: EventHotKeyRef?
        let result = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: OSType(0x434C504E), id: id), GetApplicationEventTarget(), 0, &candidate)
        guard result == noErr, let candidate else { return false }
        // Keep the old registration active until the replacement has succeeded.
        if let reference { UnregisterEventHotKey(reference) }
        reference = candidate; current = shortcut; eventID = id; pressGate.release()
        return true
    }
    func suspend() { if let reference { UnregisterEventHotKey(reference) }; reference = nil; pressGate.release() }
    deinit { suspend(); if let handler { RemoveEventHandler(handler) } }
}

