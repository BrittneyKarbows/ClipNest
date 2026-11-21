import AppKit
import Carbon

var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    checks += 1; print("PASS: \(message)")
}
func waitUntil(_ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(4)
    while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
}
func imageRepWidth(_ image: NSImage) -> Int { NSBitmapImageRep(data: image.tiffRepresentation!)!.pixelsWide }
let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClipNestTests-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: root) }
let url = root.appendingPathComponent("history.sqlite")
let store = try ClipStore(url: url)
let text = Clip.make(kind: .text, text: "你好，剪藏 ' SQL; ☀️\n第二行", source: "测试")
store.insert(text, limit: 100)
expect(store.clips.count == 1 && store.clips[0].text == text.text, "Unicode and SQL-safe round trip")
store.insert(text, limit: 100)
expect(store.clips.count == 1, "Repeated content deduplicates")
store.toggleStar(store.clips[0])
store.insert(text, limit: 100)
expect(store.clips[0].starred, "Dedup preserves favorite")
let boardID = store.addBoard("工作 ' 灵感")!
let board = Board(id: boardID, name: "工作 ' 灵感")
store.toggleBoard(store.clips[0], board: board)
expect(store.clips[0].boards.contains(boardID), "Board membership saved")
let ordinary = Clip.make(kind: .link, text: "https://example.com", source: "Safari")
store.insert(ordinary, limit: 100)
store.clearHistory()
expect(store.clips.count == 1 && store.clips[0].id == text.id, "Clear preserves favorites and board entries")
let reopened = try ClipStore(url: url)
expect(reopened.clips[0].boards.contains(boardID) && reopened.clips[0].starred, "Persistence survives database reopen")
store.deleteBoard(board)
expect(store.boards.isEmpty && store.clips[0].boards.isEmpty, "Deleting board preserves clip and cascades membership")
for i in 0..<6 { store.insert(.make(kind: .text, text: "Item \(i)", source: "Test"), limit: 2) }
expect(store.clips.count == 3 && store.clips.contains(where: { $0.starred }), "History cap preserves pinned entries")
let boardOnlyID = store.addBoard("仅分类")!
let unstarred = store.clips.first(where: { !$0.starred })!
store.toggleBoard(unstarred, board: Board(id: boardOnlyID, name: "仅分类"))
store.clearHistory()
expect(store.clips.count == 2, "Board-only entry survives history clear")
let suite = "ClipNestTests-\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let preferences = Preferences(defaults: defaults)
expect(preferences.shortcut == .defaultShortcut && preferences.showMenuBarIcon, "New preferences migrate to default shortcut and visible menu icon")
expect(preferences.theme == .system && preferences.historyRetention == .forever, "Existing users migrate to system appearance with automatic deletion disabled")
preferences.theme = .dark; preferences.historyRetention = .threeMonths
expect(Preferences(defaults: defaults).theme == .dark && Preferences(defaults: defaults).historyRetention == .threeMonths, "Appearance and retention settings persist across restart")
expect(ThemeMode.system.appearance == nil && ThemeMode.light.appearance?.name == .aqua && ThemeMode.dark.appearance?.name == .darkAqua, "System appearance clears the override while manual modes use native Aqua appearances")
defaults.set("invalid-theme", forKey: "theme"); defaults.set("invalid-retention", forKey: "historyRetention")
expect(Preferences(defaults: defaults).theme == .system && Preferences(defaults: defaults).historyRetention == .forever, "Invalid stored theme and retention safely fall back without deleting history")
preferences.theme = .system; preferences.historyRetention = .forever
expect(!preferences.doubleClickToPaste, "Double-click paste defaults off to avoid accidental dismissal")
var hotKeyGate = HotKeyPressGate()
expect(hotKeyGate.press() && !hotKeyGate.press(), "Holding a global shortcut only opens the panel once")
hotKeyGate.release()
expect(hotKeyGate.press(), "Releasing and pressing again allows the next intentional toggle")
preferences.doubleClickToPaste = true
expect(Preferences(defaults: defaults).doubleClickToPaste, "Double-click preference persists")
preferences.doubleClickToPaste = false
let panelFrame = CGRect(x: 100, y: 100, width: 1000, height: 390)
let statusFrame = CGRect(x: 900, y: 900, width: 24, height: 24)
expect(!PanelDismissalPolicy.shouldDismiss(visible: true, panelFrame: panelFrame, statusFrame: statusFrame, click: CGPoint(x: 300, y: 300), eventTime: 11, shownAt: 10), "Clicking inside panel never triggers outside-click dismissal")
expect(!PanelDismissalPolicy.shouldDismiss(visible: true, panelFrame: panelFrame, statusFrame: nil, click: CGPoint(x: 98, y: 300), eventTime: 11, shownAt: 10), "Panel border clicks are not treated as outside clicks")
expect(!PanelDismissalPolicy.shouldDismiss(visible: true, panelFrame: panelFrame, statusFrame: nil, click: .zero, eventTime: 9.9, shownAt: 10), "Queued click from before opening cannot dismiss panel")
expect(!PanelDismissalPolicy.shouldDismiss(visible: true, panelFrame: panelFrame, statusFrame: nil, click: .zero, eventTime: 10.1, shownAt: 10), "Opening click has a short dismissal grace period")
expect(!PanelDismissalPolicy.shouldDismiss(visible: true, panelFrame: panelFrame, statusFrame: statusFrame, click: CGPoint(x: 912, y: 912), eventTime: 11, shownAt: 10), "Menu-bar button handles its own toggle without dismissal races")
expect(PanelDismissalPolicy.shouldDismiss(visible: true, panelFrame: panelFrame, statusFrame: nil, click: .zero, eventTime: 11, shownAt: 10), "A real outside click dismisses an open panel")
expect(!PanelDismissalPolicy.shouldDismiss(visible: false, panelFrame: panelFrame, statusFrame: nil, click: .zero, eventTime: 11, shownAt: 10), "Hidden panel ignores outside clicks")
let custom = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(controlKey | optionKey))
preferences.saveShortcut(custom); preferences.showMenuBarIcon = false
let reloadedPreferences = Preferences(defaults: defaults)
expect(reloadedPreferences.shortcut == custom && !reloadedPreferences.showMenuBarIcon, "Shortcut and menu visibility survive restart")
expect(custom.display == "⌃⌥J", "Shortcut label includes saved key and modifiers")
let noModifier = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: 0)
expect(noModifier.validationError != nil, "Plain typing cannot become a global shortcut")
expect(KeyboardShortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(shiftKey)).validationError != nil, "Shift-only shortcut is rejected")
expect(KeyboardShortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey)).validationError != nil, "Standard copy shortcut is protected")
expect(KeyboardShortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey)).validationError != nil, "Spotlight shortcut is protected")
preferences.saveShortcut(noModifier)
expect(preferences.shortcut == custom, "Invalid shortcut cannot overwrite saved shortcut")
defaults.set(Data("invalid JSON".utf8), forKey: "panelShortcut")
expect(Preferences(defaults: defaults).shortcut == .defaultShortcut, "Corrupt shortcut preferences recover to default")
var loginState = LoginItemState.disabled
var registerCount = 0
var unregisterCount = 0
var loginFails = false
struct TestFailure: Error {}
let login = LoginItemController(backend: LoginItemBackend(state: { loginState }, register: {
    registerCount += 1
    if loginFails { throw TestFailure() }
    loginState = .pendingApproval
}, unregister: { unregisterCount += 1; loginState = .disabled }))
login.setEnabled(true)
expect(login.requested && login.state == .pendingApproval && registerCount == 1, "Login item shows pending approval without claiming enabled")
login.setEnabled(true)
expect(registerCount == 1, "Pending login item is not registered twice")
loginState = .enabled; login.refresh()
expect(login.state == .enabled, "Login item refresh picks up approval in System Settings")
login.setEnabled(false)
expect(!login.requested && unregisterCount == 1, "Login item can be disabled")
loginFails = true; login.setEnabled(true)
expect(login.error != nil && !login.requested, "Login failure preserves actual disabled state")
loginState = .pendingApproval; login.refresh(); login.setEnabled(false)
expect(login.state == .disabled && unregisterCount == 2, "Pending login item can be cancelled")
preferences.excluded = []
let pb = NSPasteboard(name: NSPasteboard.Name(suite))
defer { pb.releaseGlobally() }
var bundle = "com.test.editor"
let service = ClipboardService(store: store, preferences: preferences, pasteboard: pb, source: { ("测试编辑器", bundle) })
pb.clearContents(); let wroteURL = pb.setString("https://apple.com", forType: .string)
guard wroteURL else { fputs("Clipboard service unavailable. Run these tests in a local Terminal outside a restricted sandbox. Tests only access a uniquely named pasteboard.\n", stderr); exit(2) }
service.poll()
expect(store.clips.first?.kind == .link, "Clipboard URL recognition")
preferences.paused = true
let count = store.clips.count
pb.clearContents(); pb.setString("Paused secret", forType: .string); service.poll()
expect(store.clips.count == count, "Paused clipboard is ignored")
preferences.paused = false
preferences.excluded = ["com.test.private"]; bundle = "com.test.private"
pb.clearContents(); pb.setString("Excluded secret", forType: .string); service.poll()
expect(!store.clips.contains(where: { $0.text == "Excluded secret" }), "Excluded app is ignored")
bundle = "com.test.editor"
for type in ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType"] {
    pb.clearContents(); pb.setString("Secret \(type)", forType: .string); pb.setData(Data(), forType: .init(type)); service.poll()
    expect(!store.clips.contains(where: { $0.text == "Secret \(type)" }), "Privacy marker \(type) is ignored")
}
pb.clearContents(); pb.setString("ordinary text", forType: .string); service.poll()
expect(store.clips.first?.kind == .text && store.clips.first?.text == "ordinary text", "Plain text capture")
let captured = store.clips.first!
expect(service.copy(captured) && pb.string(forType: .string) == captured.text, "Text restored to isolated pasteboard")
service.poll()
expect(store.clips.first?.id == captured.id, "Own clipboard write is suppressed")
let image = NSImage(size: NSSize(width: 10, height: 10)); image.lockFocus(); NSColor.orange.setFill(); NSRect(x: 0, y: 0, width: 10, height: 10).fill(); image.unlockFocus()
pb.clearContents(); pb.writeObjects([image]); service.poll()
expect(store.clips.first?.kind == .image && store.clips.first?.data != nil, "Image capture and blob persistence")
expect(service.copy(store.clips.first!), "Image restored to isolated pasteboard")
let nativeImageClip = store.clips.first!
expect(pb.data(forType: .png) != nil && pb.data(forType: .tiff) != nil, "Every copied image advertises both PNG and TIFF")
let pngRepresentation = pb.data(forType: .png)!
expect(NSBitmapImageRep(data: pngRepresentation)?.pixelsWide == imageRepWidth(image), "PNG representation preserves image pixel dimensions")
expect(service.copy(nativeImageClip) && pb.string(forType: .fileURL) == nil && pb.data(forType: .png) != nil, "Image clipboard stays an image rather than an unsolicited file attachment")
let currentChange = pb.changeCount
let invalidImageClip = Clip.make(kind: .image, text: "invalid", data: Data("invalid".utf8), source: "Test")
expect(!service.copy(invalidImageClip) && pb.changeCount == currentChange, "Invalid image cannot clear the user's existing clipboard")
let screenshot = root.appendingPathComponent("Snapzy_test.png")
let imageRep = NSBitmapImageRep(data: image.tiffRepresentation!)!
let screenshotData = imageRep.representation(using: .png, properties: [:])!
try screenshotData.write(to: screenshot)
expect(ImageFilePreview.load(from: screenshot.absoluteString) == screenshotData, "PNG screenshot file can supply image data")
let dual = NSPasteboardItem()
dual.setString(screenshot.absoluteString, forType: .fileURL)
dual.setData(screenshotData, forType: .png)
pb.clearContents(); pb.writeObjects([dual]); service.poll()
expect(store.clips.first?.kind == .image && store.clips.first?.data == screenshotData, "Image bytes take priority over a single file URL")
pb.clearContents(); pb.writeObjects([screenshot as NSURL]); service.poll()
let fileClipID = Clip.make(kind: .files, text: screenshot.absoluteString, source: "Test").id
waitUntil { store.clips.first(where: { $0.id == fileClipID })?.data != nil }
let fileClip = store.clips.first(where: { $0.id == fileClipID })!
expect(fileClip.kind == .files && fileClip.hasImagePreview && fileClip.data == screenshotData, "URL-only screenshot gains a saved image preview")
expect(fileClip.kindLabel == "图片文件", "Image file is labeled as an image file")
expect(service.copy(fileClip) && pb.data(forType: .tiff) != nil && pb.string(forType: .fileURL) == screenshot.absoluteString, "Image file restores both file URL and picture representations")
store.toggleStar(fileClip)
let imageStore = try ClipStore(url: url)
expect(imageStore.clips.first(where: { $0.id == fileClipID })?.data == screenshotData, "Screenshot image persists after database reopen")
try FileManager.default.removeItem(at: screenshot)
expect(service.copy(fileClip) && pb.data(forType: .tiff) != nil && pb.string(forType: .fileURL) == nil, "Saved screenshot can still be copied after its original file is deleted")
expect(pb.data(forType: .png) != nil, "Deleted screenshot still offers standard PNG data")
expect(ImageFilePreview.load(from: screenshot.absoluteString) == nil, "Missing file falls back without an error")
let legacyScreenshot = root.appendingPathComponent("Snapzy_legacy.png")
try screenshotData.write(to: legacyScreenshot)
let legacyClip = Clip.make(kind: .files, text: legacyScreenshot.absoluteString, source: "Old version")
store.insert(legacyClip, limit: 500)
store.toggleStar(legacyClip)
store.loadFilePreviews()
waitUntil { store.clips.first(where: { $0.id == legacyClip.id })?.data != nil }
expect(store.clips.first(where: { $0.id == legacyClip.id })?.data == screenshotData && store.clips.first(where: { $0.id == legacyClip.id })?.starred == true, "Old file records gain image previews without losing favorites")
let updatedImage = NSImage(size: NSSize(width: 12, height: 12)); updatedImage.lockFocus(); NSColor.green.setFill(); NSRect(x: 0, y: 0, width: 12, height: 12).fill(); updatedImage.unlockFocus()
let updatedPNG = NSBitmapImageRep(data: updatedImage.tiffRepresentation!)!.representation(using: .png, properties: [:])!
try updatedPNG.write(to: legacyScreenshot)
pb.clearContents(); pb.writeObjects([legacyScreenshot as NSURL]); service.poll()
waitUntil { store.clips.first(where: { $0.id == legacyClip.id })?.data == updatedPNG }
expect(store.clips.first(where: { $0.id == legacyClip.id })?.data == updatedPNG && store.clips.first(where: { $0.id == legacyClip.id })?.starred == true, "Recopying a modified image at the same path refreshes its preview and preserves favorites")
let invalid = root.appendingPathComponent("not_an_image.png")
try Data("not a PNG".utf8).write(to: invalid)
expect(ImageFilePreview.load(from: invalid.absoluteString) == nil, "Invalid image file falls back safely")
expect(ImageFilePreview.load(from: root.absoluteString) == nil, "Directories are not loaded as images")
expect(ImageFilePreview.load(from: "https://example.com/image.png") == nil, "Image file previews never download remote URLs")
expect(ImageFilePreview.load(from: legacyScreenshot.absoluteString + "\n" + legacyScreenshot.absoluteString) == nil, "Multiple files are not collapsed into one picture")
let oversized = root.appendingPathComponent("too_large.png")
FileManager.default.createFile(atPath: oversized.path, contents: Data())
let handle = try FileHandle(forWritingTo: oversized)
try handle.truncate(atOffset: UInt64(ImageFilePreview.byteLimit + 1)); try handle.close()
expect(ImageFilePreview.load(from: oversized.absoluteString) == nil, "Oversized image file respects the storage limit")
let files = [URL(fileURLWithPath: "/tmp/one.txt"), URL(fileURLWithPath: "/tmp/two.txt")]
pb.clearContents(); pb.writeObjects(files as [NSURL]); service.poll()
expect(store.clips.first?.kind == .files && store.clips.first?.text.components(separatedBy: "\n").count == 2, "Multiple file URLs captured")
expect(service.copy(store.clips.first!), "File URLs restored")
let restoredFiles = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
expect(restoredFiles == files, "Multiple file URL fidelity")
let firstFile = NSPasteboardItem(); firstFile.setString(files[0].absoluteString, forType: .fileURL); firstFile.setData(screenshotData, forType: .png)
let secondFile = NSPasteboardItem(); secondFile.setString(files[1].absoluteString, forType: .fileURL)
pb.clearContents(); pb.writeObjects([firstFile, secondFile]); service.poll()
expect(store.clips.first?.kind == .files && store.clips.first?.text.components(separatedBy: "\n").count == 2, "Multiple selected files stay intact even when an image representation exists")
store.delete(captured)
expect(!store.clips.contains(where: { $0.id == captured.id }), "Individual deletion")
expect(store.error == nil, "No database errors")
// Age-based cleanup uses an isolated database and a fixed clock, never live data.
let iso = ISO8601DateFormatter()
func instant(_ value: String) -> Date { iso.date(from: value)! }
var utcCalendar = Calendar(identifier: .gregorian); utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
let cleanupNow = instant("2026-05-31T12:00:00Z")
let cutoff = instant("2026-04-30T12:00:00Z")
expect(HistoryRetention.forever.cutoff(relativeTo: cleanupNow, calendar: utcCalendar) == nil, "Forever retention has no expiration cutoff")
expect(HistoryRetention.month.cutoff(relativeTo: cleanupNow, calendar: utcCalendar) == cutoff, "One-month retention uses the calendar month at month end")
expect(HistoryRetention.threeMonths.cutoff(relativeTo: cleanupNow, calendar: utcCalendar) == instant("2026-02-28T12:00:00Z"), "Three-month retention handles February correctly")
expect(HistoryRetention.year.cutoff(relativeTo: instant("2024-02-29T12:00:00Z"), calendar: utcCalendar) == instant("2023-02-28T12:00:00Z"), "One-year retention handles leap day")
expect(HistoryRetention.week.cutoff(relativeTo: cleanupNow, calendar: utcCalendar) == instant("2026-05-24T12:00:00Z"), "Weekly retention subtracts seven calendar days")
expect(HistoryRetention.sixMonths.cutoff(relativeTo: cleanupNow, calendar: utcCalendar) == instant("2025-11-30T12:00:00Z"), "Six-month retention handles shorter months")
func agedClip(_ name: String, updated: Date, kind: ClipKind = .text, data: Data? = nil) -> Clip {
    let base = Clip.make(kind: kind, text: name, data: data, source: "Age tests")
    return Clip(id: base.id, kind: kind, text: name, data: data, source: base.source, bundleID: "", created: instant("2025-01-01T12:00:00Z"), updated: updated, starred: false, boards: [])
}
let ageURL = root.appendingPathComponent("expiration.sqlite")
let ageStore = try ClipStore(url: ageURL)
let expired = agedClip("expired ordinary", updated: instant("2026-04-29T12:00:00Z"))
let expiredImage = agedClip("expired image", updated: instant("2026-01-04T12:00:00Z"), kind: .image, data: screenshotData)
let boundary = agedClip("at cutoff", updated: cutoff)
let recent = agedClip("recent", updated: instant("2026-05-30T12:00:00Z"))
let oldStar = agedClip("protected star", updated: instant("2026-01-01T12:00:00Z"))
let oldBoard = agedClip("protected board", updated: instant("2026-01-02T12:00:00Z"))
let recopied = agedClip("old creation, recent copy", updated: instant("2026-05-29T12:00:00Z"))
for item in [expired, expiredImage, boundary, recent, oldStar, oldBoard, recopied] { ageStore.insert(item, limit: 500) }
ageStore.toggleStar(oldStar)
let ageBoard = Board(id: ageStore.addBoard("Keep")!, name: "Keep"); ageStore.toggleBoard(oldBoard, board: ageBoard)
expect(ageStore.expiredCount(retention: .forever, now: cleanupNow, calendar: utcCalendar) == 0 && ageStore.pruneExpired(retention: .forever, now: cleanupNow, calendar: utcCalendar) == 0 && ageStore.clips.count == 7, "Disabled retention never deletes old records")
expect(ageStore.expiredCount(retention: .month, now: cleanupNow, calendar: utcCalendar) == 2, "Expiration preview counts only unprotected records older than the cutoff")
expect(ageStore.pruneExpired(retention: .month, now: cleanupNow, calendar: utcCalendar) == 2 && ageStore.clips.count == 5, "Age cleanup removes expired text and image history")
expect(ageStore.clips.contains(where: { $0.id == boundary.id }) && ageStore.clips.contains(where: { $0.id == recent.id }), "Boundary and recent records survive cleanup")
expect(ageStore.clips.contains(where: { $0.id == oldStar.id && $0.starred }) && ageStore.clips.contains(where: { $0.id == oldBoard.id && $0.boards.contains(ageBoard.id) }), "Favorites and board-only records survive age cleanup")
expect(ageStore.clips.contains(where: { $0.id == recopied.id }), "Retention is based on last copy time rather than original creation")
expect(ageStore.pruneExpired(retention: .month, now: cleanupNow, calendar: utcCalendar) == 0, "Repeated cleanup is idempotent")
let ageReopened = try ClipStore(url: ageURL)
expect(Set(ageReopened.clips.map(\.id)) == Set(ageStore.clips.map(\.id)), "Expiration changes persist after reopening the database")
let cleanupSuite = suite + "-cleanup"; let cleanupDefaults = UserDefaults(suiteName: cleanupSuite)!
defer { cleanupDefaults.removePersistentDomain(forName: cleanupSuite) }
let cleanupPreferences = Preferences(defaults: cleanupDefaults)
var movingClock = cleanupNow
let cleaner = HistoryCleanupService(store: ageStore, preferences: cleanupPreferences, clock: { movingClock })
let newlyExpired = agedClip("service cleanup", updated: instant("2026-01-05T12:00:00Z"))
ageStore.insert(newlyExpired, limit: 500); cleaner.start()
expect(ageStore.clips.contains(where: { $0.id == newlyExpired.id }), "Starting the cleanup service with default settings preserves history")
cleanupPreferences.historyRetention = .month
expect(!ageStore.clips.contains(where: { $0.id == newlyExpired.id }), "Changing retention activates cleanup immediately with the new policy")
movingClock = instant("2026-07-31T12:00:00Z"); cleaner.run()
expect(!ageStore.clips.contains(where: { $0.id == recent.id }) && ageStore.clips.contains(where: { $0.id == oldStar.id }) && ageStore.clips.contains(where: { $0.id == oldBoard.id }), "A later periodic or wake cleanup expires newly old records while preserving protected ones")
cleanupPreferences.historyRetention = .forever
let disabledOld = agedClip("disabled cleanup", updated: instant("2026-01-06T12:00:00Z")); ageStore.insert(disabledOld, limit: 500); cleaner.run()
expect(ageStore.clips.contains(where: { $0.id == disabledOld.id }), "Turning off retention stops future automatic deletions")
cleaner.stop(); cleanupPreferences.historyRetention = .month
expect(ageStore.clips.contains(where: { $0.id == disabledOld.id }), "Stopping the cleanup service removes settings observers")
expect(ageStore.error == nil, "Age-based cleanup completes without database errors")
// Exercise actual Carbon registration without replacing the user's panel shortcut.
let firstKey = KeyboardShortcut(keyCode: UInt32(kVK_F18), modifiers: UInt32(cmdKey | controlKey | optionKey))
let secondKey = KeyboardShortcut(keyCode: UInt32(kVK_F19), modifiers: UInt32(cmdKey | controlKey | optionKey))
let registration = HotKey()
let occupied = HotKey()
expect(registration.register(firstKey), "Global shortcut can be registered")
expect(occupied.register(secondKey), "Independent registration can reserve another shortcut")
expect(!registration.register(secondKey) && registration.current == firstKey && registration.isRegistered, "Shortcut conflict preserves original registration")
occupied.suspend()
expect(registration.register(secondKey) && registration.current == secondKey, "Shortcut can change after conflict clears")
let released = HotKey()
expect(released.register(firstKey), "Changing shortcut releases the previous key")
released.suspend(); registration.suspend()
expect(!registration.isRegistered && registration.register(secondKey), "Recording cancellation can restore suspended shortcut")
registration.suspend()
print("\(checks) checks passed. All tests use an isolated database and pasteboard.")
