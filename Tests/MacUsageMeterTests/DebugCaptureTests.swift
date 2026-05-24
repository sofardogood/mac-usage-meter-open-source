import XCTest
import SQLite3
@testable import MacUsageMeter

final class DebugCaptureTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DebugCaptureTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func test_insertDebugCapture_persistsRawOutput() throws {
        let dbPath = tempDir.appendingPathComponent("monitor.sqlite3").path
        let db = try DatabaseManager(dbPath: dbPath)

        try db.insertDebugCapture(
            id: "capture-1",
            capturedAtMs: 1_774_051_200_000,
            command: "/usr/bin/powermetrics --sample-count 1",
            rawStdout: "<plist>stdout</plist>",
            rawStderr: "stderr text",
            exitCode: 7,
            relatedSampleId: nil
        )

        let row = try fetchDebugCapture(dbPath: dbPath, id: "capture-1")
        XCTAssertEqual(row.command, "/usr/bin/powermetrics --sample-count 1")
        XCTAssertEqual(row.rawStdout, "<plist>stdout</plist>")
        XCTAssertEqual(row.rawStderr, "stderr text")
        XCTAssertEqual(row.exitCode, 7)
    }

    private func fetchDebugCapture(dbPath: String, id: String) throws -> (command: String, rawStdout: String?, rawStderr: String?, exitCode: Int32?) {
        var handle: OpaquePointer?
        let openRc = sqlite3_open_v2(dbPath, &handle, SQLITE_OPEN_READONLY, nil)
        guard openRc == SQLITE_OK, let db = handle else {
            sqlite3_close(handle)
            throw NSError(domain: "DebugCaptureTests", code: Int(openRc))
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let sql = "SELECT command, raw_stdout, raw_stderr, exit_code FROM debug_captures WHERE id = ?"
        let prepareRc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard prepareRc == SQLITE_OK else {
            throw NSError(domain: "DebugCaptureTests", code: Int(prepareRc))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw NSError(domain: "DebugCaptureTests", code: 404)
        }

        let command = String(cString: sqlite3_column_text(stmt, 0))
        let rawStdout = sqlite3_column_type(stmt, 1) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 1))
        let rawStderr = sqlite3_column_type(stmt, 2) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 2))
        let exitCode = sqlite3_column_type(stmt, 3) == SQLITE_NULL ? nil : sqlite3_column_int(stmt, 3)
        return (command, rawStdout, rawStderr, exitCode)
    }
}
