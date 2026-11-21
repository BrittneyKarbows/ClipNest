import Foundation
import SQLite3
import AppKit
import Combine

enum StoreError: LocalizedError {
    case database(String)
    var errorDescription: String? { if case .database(let message) = self { return "本地数据库：\(message)" }; return nil }
}

final class ClipStore: ObservableObject {
    @Published private(set) var clips: [Clip] = []
    @Published private(set) var boards: [Board] = []
    @Published var error: String?
    let url: URL
    private var db: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private var attemptedFilePreviews: Set<String> = []
    private var loadingFilePreviews = false
    private var requestedFilePreviewRefresh: Set<String> = []

    init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw StoreError.database("无法打开存储文件") }
        do {
            try run("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;")
            try run("""
            CREATE TABLE IF NOT EXISTS clips(id TEXT PRIMARY KEY, kind TEXT NOT NULL, content TEXT NOT NULL, payload BLOB, source TEXT NOT NULL, bundle TEXT NOT NULL, created REAL NOT NULL, updated REAL NOT NULL, starred INTEGER NOT NULL DEFAULT 0);
            CREATE TABLE IF NOT EXISTS boards(id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE);
            CREATE TABLE IF NOT EXISTS memberships(clip TEXT REFERENCES clips(id) ON DELETE CASCADE, board TEXT REFERENCES boards(id) ON DELETE CASCADE, PRIMARY KEY(clip,board));
            CREATE INDEX IF NOT EXISTS clips_updated ON clips(updated DESC);
            """)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            try reload()
        } catch { sqlite3_close(db); db = nil; throw error }
    }
    deinit { sqlite3_close(db) }
    private func message() -> String { db.map { String(cString: sqlite3_errmsg($0)) } ?? "数据库未打开" }
    private func run(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw StoreError.database(message()) }
    }
    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw StoreError.database(message()) }
        return statement
    }
    private func bind(_ value: String, _ index: Int32, _ statement: OpaquePointer) { sqlite3_bind_text(statement, index, value, -1, transient) }
    private func finish(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw StoreError.database(message()) }
    }
    private func string(_ statement: OpaquePointer, _ column: Int32) -> String { sqlite3_column_text(statement, column).map { String(cString: $0) } ?? "" }
    private func change(_ operation: () throws -> Void) {
        do { try operation(); try reload() } catch { self.error = error.localizedDescription }
    }
    func reload() throws {
        var memberships: [String: Set<String>] = [:]
        let m = try prepare("SELECT clip,board FROM memberships"); defer { sqlite3_finalize(m) }
        while sqlite3_step(m) == SQLITE_ROW { memberships[string(m, 0), default: []].insert(string(m, 1)) }
        let b = try prepare("SELECT id,name FROM boards ORDER BY name COLLATE NOCASE"); defer { sqlite3_finalize(b) }
        var newBoards: [Board] = []
        while sqlite3_step(b) == SQLITE_ROW { newBoards.append(Board(id: string(b, 0), name: string(b, 1))) }
        let s = try prepare("SELECT id,kind,content,payload,source,bundle,created,updated,starred FROM clips ORDER BY updated DESC"); defer { sqlite3_finalize(s) }
        var newClips: [Clip] = []
        while sqlite3_step(s) == SQLITE_ROW {
            let id = string(s, 0)
            let data = sqlite3_column_blob(s, 3).map { Data(bytes: $0, count: Int(sqlite3_column_bytes(s, 3))) }
            newClips.append(Clip(id: id, kind: ClipKind(rawValue: string(s, 1)) ?? .text, text: string(s, 2), data: data, source: string(s, 4), bundleID: string(s, 5), created: Date(timeIntervalSince1970: sqlite3_column_double(s, 6)), updated: Date(timeIntervalSince1970: sqlite3_column_double(s, 7)), starred: sqlite3_column_int(s, 8) != 0, boards: memberships[id] ?? []))
        }
        boards = newBoards; clips = newClips
    }
    func loadFilePreviews(retrying id: String? = nil) {
        if let id { attemptedFilePreviews.remove(id); requestedFilePreviewRefresh.insert(id) }
        guard !loadingFilePreviews else { return }
        let pending = clips.filter { $0.kind == .files && ($0.data == nil || requestedFilePreviewRefresh.contains($0.id)) && !attemptedFilePreviews.contains($0.id) }
        guard !pending.isEmpty else { return }
        attemptedFilePreviews.formUnion(pending.map(\.id))
        requestedFilePreviewRefresh.subtract(pending.map(\.id))
        loadingFilePreviews = true
        loadNextPreview(pending, at: 0)
    }
    private func loadNextPreview(_ pending: [Clip], at index: Int) {
        guard index < pending.count else { loadingFilePreviews = false; loadFilePreviews(); return }
        let clip = pending[index]
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let data = ImageFilePreview.load(from: clip.text)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let data { self.change {
                    let s = try self.prepare("UPDATE clips SET payload=? WHERE id=? AND kind='files'")
                    defer { sqlite3_finalize(s) }
                    _ = data.withUnsafeBytes { sqlite3_bind_blob(s, 1, $0.baseAddress, Int32(data.count), self.transient) }
                    self.bind(clip.id, 2, s); try self.finish(s)
                } }
                self.loadNextPreview(pending, at: index + 1)
            }
        }
    }
    func insert(_ clip: Clip, limit: Int) {
        change {
            let s = try prepare("INSERT INTO clips(id,kind,content,payload,source,bundle,created,updated,starred) VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET updated=excluded.updated, source=excluded.source,bundle=excluded.bundle")
            defer { sqlite3_finalize(s) }
            bind(clip.id, 1, s); bind(clip.kind.rawValue, 2, s); bind(clip.text, 3, s)
            if let data = clip.data { _ = data.withUnsafeBytes { sqlite3_bind_blob(s, 4, $0.baseAddress, Int32(data.count), transient) } } else { sqlite3_bind_null(s, 4) }
            bind(clip.source, 5, s); bind(clip.bundleID, 6, s)
            sqlite3_bind_double(s, 7, clip.created.timeIntervalSince1970); sqlite3_bind_double(s, 8, clip.updated.timeIntervalSince1970); sqlite3_bind_int(s, 9, clip.starred ? 1 : 0)
            try finish(s); try pruneSQL(limit)
        }
    }
    private func pruneSQL(_ limit: Int) throws {
        try run("DELETE FROM clips WHERE starred=0 AND id NOT IN (SELECT clip FROM memberships) AND id NOT IN (SELECT id FROM clips ORDER BY updated DESC LIMIT \(max(1, limit)))")
    }
    func prune(limit: Int) { change { try pruneSQL(limit) } }
    func expiredCount(retention: HistoryRetention, now: Date = Date(), calendar: Calendar = .current) -> Int {
        guard let cutoff = retention.cutoff(relativeTo: now, calendar: calendar) else { return 0 }
        do {
            let s = try prepare("SELECT COUNT(*) FROM clips WHERE updated < ? AND starred=0 AND id NOT IN (SELECT clip FROM memberships)")
            defer { sqlite3_finalize(s) }
            sqlite3_bind_double(s, 1, cutoff.timeIntervalSince1970)
            guard sqlite3_step(s) == SQLITE_ROW else { throw StoreError.database(message()) }
            return Int(sqlite3_column_int(s, 0))
        } catch { self.error = error.localizedDescription; return 0 }
    }
    @discardableResult func pruneExpired(retention: HistoryRetention, now: Date = Date(), calendar: Calendar = .current) -> Int {
        guard let cutoff = retention.cutoff(relativeTo: now, calendar: calendar), expiredCount(retention: retention, now: now, calendar: calendar) > 0 else { return 0 }
        var removed = 0
        change {
            let s = try prepare("DELETE FROM clips WHERE updated < ? AND starred=0 AND id NOT IN (SELECT clip FROM memberships)")
            defer { sqlite3_finalize(s) }
            sqlite3_bind_double(s, 1, cutoff.timeIntervalSince1970); try finish(s)
            removed = Int(sqlite3_changes(db))
        }
        return removed
    }
    func toggleStar(_ clip: Clip) { change {
        let s = try prepare("UPDATE clips SET starred=? WHERE id=?"); defer { sqlite3_finalize(s) }
        sqlite3_bind_int(s, 1, clip.starred ? 0 : 1); bind(clip.id, 2, s); try finish(s)
    } }
    func delete(_ clip: Clip) { change {
        let s = try prepare("DELETE FROM clips WHERE id=?"); defer { sqlite3_finalize(s) }; bind(clip.id, 1, s); try finish(s)
    } }
    func clearHistory() { change { try run("DELETE FROM clips WHERE starred=0 AND id NOT IN (SELECT clip FROM memberships)"); try run("PRAGMA wal_checkpoint(TRUNCATE); VACUUM;") } }
    @discardableResult func addBoard(_ name: String) -> String? {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
        guard !name.isEmpty else { return nil }
        let id = UUID().uuidString
        var saved = false
        change { let s = try prepare("INSERT INTO boards(id,name) VALUES(?,?)"); defer { sqlite3_finalize(s) }; bind(id, 1, s); bind(name, 2, s); try finish(s); saved = true }
        return saved ? id : nil
    }
    func deleteBoard(_ board: Board) { change {
        let s = try prepare("DELETE FROM boards WHERE id=?"); defer { sqlite3_finalize(s) }; bind(board.id, 1, s); try finish(s)
    } }
    func toggleBoard(_ clip: Clip, board: Board) { change {
        let sql = clip.boards.contains(board.id) ? "DELETE FROM memberships WHERE clip=? AND board=?" : "INSERT OR IGNORE INTO memberships(clip,board) VALUES(?,?)"
        let s = try prepare(sql); defer { sqlite3_finalize(s) }; bind(clip.id, 1, s); bind(board.id, 2, s); try finish(s)
    } }
}

final class HistoryCleanupService {
    private let store: ClipStore
    private let preferences: Preferences
    private let clock: () -> Date
    private var timer: Timer?
    private var subscriptions = Set<AnyCancellable>()
    init(store: ClipStore, preferences: Preferences = .shared, clock: @escaping () -> Date = { Date() }) { self.store = store; self.preferences = preferences; self.clock = clock }
    func start() {
        stop()
        preferences.$historyRetention.removeDuplicates().sink { [weak self] retention in self?.clean(using: retention) }.store(in: &subscriptions)
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in self?.run() }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification).sink { [weak self] _ in self?.run() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification).sink { [weak self] _ in self?.run() }.store(in: &subscriptions)
    }
    func run() { clean(using: preferences.historyRetention) }
    private func clean(using retention: HistoryRetention) { store.pruneExpired(retention: retention, now: clock()) }
    func stop() { timer?.invalidate(); timer = nil; subscriptions.removeAll() }
    deinit { stop() }
}
