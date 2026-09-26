import Foundation
import SQLite3

/// Read-only access to another browser's SQLite database, through a private copy:
/// the browser may be running and holding locks, and its recent writes may still be
/// in the `-wal` file, which is copied along and replayed when the copy opens.
final class SQLiteDatabase {
    private var handle: OpaquePointer?
    private let folder: URL

    enum Failure: Error { case unreadable(URL), query(String) }

    init(copying url: URL) throws {
        let manager = FileManager.default
        folder = manager.temporaryDirectory.appendingPathComponent("wake-import-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appendingPathComponent(url.lastPathComponent)
        do {
            try manager.copyItem(at: url, to: copy)
        } catch {
            try? manager.removeItem(at: folder)
            throw Failure.unreadable(url)
        }
        for suffix in ["-wal", "-shm"] {
            let side = URL(fileURLWithPath: url.path + suffix)
            if manager.fileExists(atPath: side.path) {
                try? manager.copyItem(at: side, to: URL(fileURLWithPath: copy.path + suffix))
            }
        }
        guard sqlite3_open_v2(copy.path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            try? manager.removeItem(at: folder)
            throw Failure.unreadable(url)
        }
    }

    deinit {
        sqlite3_close(handle)
        try? FileManager.default.removeItem(at: folder)
    }

    /// Runs `sql`, calling `row` for each result.
    func rows(_ sql: String, _ row: (Row) -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw Failure.query(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW { row(Row(statement: statement)) }
    }

    /// The first column of the first row, as text.
    func scalar(_ sql: String) -> String? {
        var value: String?
        try? rows(sql) { value = value ?? $0.text(0) }
        return value
    }

    struct Row {
        let statement: OpaquePointer?

        func text(_ column: Int32) -> String? {
            guard let pointer = sqlite3_column_text(statement, column) else { return nil }
            return String(cString: pointer)
        }

        func int(_ column: Int32) -> Int64 { sqlite3_column_int64(statement, column) }

        func double(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }

        func data(_ column: Int32) -> Data {
            let count = Int(sqlite3_column_bytes(statement, column))
            guard count > 0, let bytes = sqlite3_column_blob(statement, column) else { return Data() }
            return Data(bytes: bytes, count: count)
        }
    }
}
