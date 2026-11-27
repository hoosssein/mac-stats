#if os(macOS)
import Foundation
import SQLite3
import StatsCore

/// Data layer: saves history tiers 1–3 to SQLite so they survive restarts.
/// Uses the system SQLite library directly (docs/kb/stack.md deviation D2).
public actor HistoryDatabase {
    public struct Row: Sendable {
        public var key: String
        public var tier: Int
        public var bucket: Bucket

        public init(key: String, tier: Int, bucket: Bucket) { self.key = key; self.tier = tier; self.bucket = bucket }
    }

    public let url: URL
    private var db: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public static var defaultURL: URL { ConfigStore.supportDirectory.appendingPathComponent("history.sqlite") }

    public init(url: URL = HistoryDatabase.defaultURL) {
        self.url = url
    }

    private func open() -> OpaquePointer? {
        if let db { return db }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            return nil
        }
        db = handle
        exec("PRAGMA journal_mode=WAL")
        exec("""
            CREATE TABLE IF NOT EXISTS buckets (
              key TEXT NOT NULL, tier INTEGER NOT NULL, t REAL NOT NULL,
              min REAL NOT NULL, max REAL NOT NULL, sum REAL NOT NULL, count INTEGER NOT NULL,
              PRIMARY KEY (key, tier, t)) WITHOUT ROWID
            """)
        return db
    }

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        guard let db else { return false }
        return sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    /// Writes buckets (insert or replace) in one transaction.
    public func save(_ rows: [Row]) {
        guard !rows.isEmpty, let db = open() else { return }
        exec("BEGIN")
        var stmt: OpaquePointer?
        let sql = "INSERT OR REPLACE INTO buckets (key, tier, t, min, max, sum, count) VALUES (?, ?, ?, ?, ?, ?, ?)"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { exec("ROLLBACK"); return }
        for r in rows {
            sqlite3_bind_text(stmt, 1, r.key, -1, transient)
            sqlite3_bind_int(stmt, 2, Int32(r.tier))
            sqlite3_bind_double(stmt, 3, r.bucket.t)
            sqlite3_bind_double(stmt, 4, Double(r.bucket.min))
            sqlite3_bind_double(stmt, 5, Double(r.bucket.max))
            sqlite3_bind_double(stmt, 6, Double(r.bucket.sum))
            sqlite3_bind_int(stmt, 7, r.bucket.count)
            sqlite3_step(stmt)
            sqlite3_reset(stmt)
        }
        sqlite3_finalize(stmt)
        exec("COMMIT")
    }

    /// Loads all saved buckets, oldest first.
    public func load() -> [Row] {
        guard let db = open() else { return [] }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT key, tier, t, min, max, sum, count FROM buckets ORDER BY key, tier, t",
                                 -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var rows: [Row] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let k = sqlite3_column_text(stmt, 0) else { continue }
            let b = Bucket(t: sqlite3_column_double(stmt, 2), min: Float(sqlite3_column_double(stmt, 3)),
                           max: Float(sqlite3_column_double(stmt, 4)), sum: Float(sqlite3_column_double(stmt, 5)),
                           count: sqlite3_column_int(stmt, 6))
            rows.append(Row(key: String(cString: k), tier: Int(sqlite3_column_int(stmt, 1)), bucket: b))
        }
        return rows
    }

    /// Removes buckets older than each tier keeps them.
    public func prune(now: Double, keepDays: Int) {
        guard open() != nil else { return }
        let specs = TieredSeries.specs(keepDays: keepDays)
        for tier in 1..<specs.count {
            exec("DELETE FROM buckets WHERE tier = \(tier) AND t < \(now - specs[tier].keep)")
        }
        exec("DELETE FROM buckets WHERE tier = 0")
    }

    public func deleteAll() {
        guard open() != nil else { return }
        exec("DELETE FROM buckets")
        exec("VACUUM")
    }

    /// Size of the database files in bytes.
    public func fileSize() -> Double {
        let fm = FileManager.default
        return [url.path, url.path + "-wal", url.path + "-shm"].reduce(0.0) { total, path in
            let attrs = try? fm.attributesOfItem(atPath: path)
            return total + ((attrs?[.size] as? NSNumber)?.doubleValue ?? 0)
        }
    }
}
#endif
