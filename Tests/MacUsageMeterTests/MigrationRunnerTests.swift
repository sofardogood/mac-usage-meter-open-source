import XCTest
import SQLite3
@testable import MacUsageMeter

/// マイグレーションランナーの単体テスト (第16.1節)
///
/// 観点: user_version 更新、失敗時のバックアップ復旧
/// 仕様書 10.9 に基づく
/// DB テストはインメモリ SQLite (:memory:) またはテンポラリファイルを使用する。
final class MigrationRunnerTests: XCTestCase {

    var runner: MigrationRunner!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        runner = MigrationRunner()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MigrationRunnerTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Version Management

    /// 初期状態 (user_version=0) から version 1 へのマイグレーション
    func test_migration_version0To1_schemaCreated() throws {
        let dbPath = createEmptyDB()

        // user_version should start at 0
        let initialVersion = try runner.getCurrentVersion(dbPath: dbPath)
        XCTAssertEqual(initialVersion, 0)

        // Run migration
        try runner.runMigrations(dbPath: dbPath)

        // user_version should now be 1
        let newVersion = try runner.getCurrentVersion(dbPath: dbPath)
        XCTAssertEqual(newVersion, MigrationRunner.targetVersion)

        // Verify tables exist by querying them
        let db = try openDB(path: dbPath)
        defer { sqlite3_close(db) }

        let tables = try listTables(db: db)
        XCTAssertTrue(tables.contains("power_samples"))
        XCTAssertTrue(tables.contains("wifi_samples"))
        XCTAssertTrue(tables.contains("daily_rollups"))
        XCTAssertTrue(tables.contains("app_settings"))
        XCTAssertTrue(tables.contains("audit_events"))
        XCTAssertTrue(tables.contains("maintenance_log"))
        XCTAssertTrue(tables.contains("debug_captures"))
    }

    /// 既に最新の場合はマイグレーションをスキップ
    func test_migration_alreadyUpToDate_noChanges() throws {
        let dbPath = createEmptyDB()

        // Run migration first time
        try runner.runMigrations(dbPath: dbPath)
        let version1 = try runner.getCurrentVersion(dbPath: dbPath)
        XCTAssertEqual(version1, MigrationRunner.targetVersion)

        // Run migration again - should succeed without error
        try runner.runMigrations(dbPath: dbPath)
        let version2 = try runner.getCurrentVersion(dbPath: dbPath)
        XCTAssertEqual(version2, MigrationRunner.targetVersion)
    }

    /// user_version の更新が正しく行われること
    func test_migration_versionUpdate_correctValue() throws {
        let dbPath = createEmptyDB()

        try runner.runMigrations(dbPath: dbPath)

        let version = try runner.getCurrentVersion(dbPath: dbPath)
        XCTAssertEqual(version, 1, "user_version should be 1 after initial migration")
    }

    // MARK: - Backup

    /// マイグレーション前にバックアップが作成されること
    func test_migration_backupCreated_bakFileExists() throws {
        let dbPath = createEmptyDB()

        try runner.runMigrations(dbPath: dbPath)

        let bakPath = dbPath + ".bak"
        XCTAssertTrue(FileManager.default.fileExists(atPath: bakPath),
                      "Backup file should be created at \(bakPath)")
    }

    /// バックアップの作成を個別にテスト
    func test_backup_createBackup_fileCreated() throws {
        let dbPath = createEmptyDB()

        // Insert some data to verify backup content
        let db = try openDB(path: dbPath)
        try executeSQL(db: db, sql: "CREATE TABLE test_table (id INTEGER PRIMARY KEY);")
        try executeSQL(db: db, sql: "INSERT INTO test_table VALUES (1);")
        sqlite3_close(db)

        try runner.createBackup(dbPath: dbPath)

        let bakPath = dbPath + ".bak"
        XCTAssertTrue(FileManager.default.fileExists(atPath: bakPath))

        // Verify backup contains the data
        let bakDB = try openDB(path: bakPath)
        defer { sqlite3_close(bakDB) }
        let tables = try listTables(db: bakDB)
        XCTAssertTrue(tables.contains("test_table"))
    }

    /// バックアップからの復旧が正しく行われること
    func test_restore_fromBackup_originalDataRestored() throws {
        let dbPath = createEmptyDB()

        // Create initial DB with test data
        let db1 = try openDB(path: dbPath)
        try executeSQL(db: db1, sql: "CREATE TABLE original_table (id INTEGER PRIMARY KEY);")
        try executeSQL(db: db1, sql: "INSERT INTO original_table VALUES (42);")
        sqlite3_close(db1)

        // Create backup
        try runner.createBackup(dbPath: dbPath)

        // Corrupt the DB by overwriting
        let db2 = try openDB(path: dbPath)
        try executeSQL(db: db2, sql: "DROP TABLE original_table;")
        try executeSQL(db: db2, sql: "CREATE TABLE corrupted_table (id INTEGER);")
        sqlite3_close(db2)

        // Restore from backup
        let restored = try runner.restoreFromBackup(dbPath: dbPath)
        XCTAssertTrue(restored)

        // Verify original data is back
        let db3 = try openDB(path: dbPath)
        defer { sqlite3_close(db3) }
        let tables = try listTables(db: db3)
        XCTAssertTrue(tables.contains("original_table"), "original_table should be restored")
        XCTAssertFalse(tables.contains("corrupted_table"), "corrupted_table should not exist")
    }

    // MARK: - Failure

    /// マイグレーション失敗時にバックアップから復旧を試みること
    /// (不正な SQL をマイグレーションとして適用するシナリオは
    ///  MigrationRunner のインターフェースに依存するため、
    ///  ここではバックアップ→復旧のフロー確認に留める)
    func test_migrationFailure_restoresBackup_originalPreserved() throws {
        let dbPath = createEmptyDB()

        // Create backup manually (simulating pre-migration backup)
        let db = try openDB(path: dbPath)
        try executeSQL(db: db, sql: "CREATE TABLE preserved_data (id INTEGER);")
        try executeSQL(db: db, sql: "INSERT INTO preserved_data VALUES (999);")
        sqlite3_close(db)

        try runner.createBackup(dbPath: dbPath)

        // Simulate corruption
        let db2 = try openDB(path: dbPath)
        try executeSQL(db: db2, sql: "DROP TABLE preserved_data;")
        sqlite3_close(db2)

        // Restore
        let restored = try runner.restoreFromBackup(dbPath: dbPath)
        XCTAssertTrue(restored)

        // Verify
        let db3 = try openDB(path: dbPath)
        defer { sqlite3_close(db3) }
        let tables = try listTables(db: db3)
        XCTAssertTrue(tables.contains("preserved_data"))
    }


    /// 開いた DB ハンドルを保持したまま backup API で復旧できること
    func test_restoreIntoOpenHandle_restoresOriginalData() throws {
        let dbPath = createEmptyDB()
        let db = try openDB(path: dbPath)
        defer { sqlite3_close(db) }

        try executeSQL(db: db, sql: "CREATE TABLE original_data (id INTEGER PRIMARY KEY, value TEXT);")
        try executeSQL(db: db, sql: "INSERT INTO original_data VALUES (1, 'before');")
        try runner.createBackup(db: db, dbPath: dbPath)

        try executeSQL(db: db, sql: "DROP TABLE original_data;")
        try executeSQL(db: db, sql: "CREATE TABLE corrupted_data (id INTEGER);")

        let restored = try runner.restoreFromBackup(into: db, dbPath: dbPath)
        XCTAssertTrue(restored)

        let tables = try listTables(db: db)
        XCTAssertTrue(tables.contains("original_data"))
        XCTAssertFalse(tables.contains("corrupted_data"))
        XCTAssertEqual(try scalarString(db: db, sql: "SELECT value FROM original_data WHERE id = 1;"), "before")
    }

    /// バックアップ復旧: バックアップファイルが存在しない場合
    func test_restoreFromBackup_noBackupFile_returnsFalseOrThrows() throws {
        let dbPath = tempDir.appendingPathComponent("nonexistent.sqlite3").path

        // No backup file exists
        do {
            let result = try runner.restoreFromBackup(dbPath: dbPath)
            // If it returns false instead of throwing, that's also acceptable
            XCTAssertFalse(result, "Should return false when backup doesn't exist")
        } catch {
            // Throwing is also acceptable
        }
    }

    // MARK: - DDL

    /// version 1 の DDL が Schema.initialDDL と一致すること
    func test_version1DDL_matchesSchemaInitialDDL() {
        let sql = runner.migrationSQL(for: 1)
        XCTAssertEqual(sql, Schema.initialDDL)
    }

    /// targetVersion が 1 であること
    func test_targetVersion_isOne() {
        XCTAssertEqual(MigrationRunner.targetVersion, 1)
    }

    // MARK: - In-Memory DB Tests

    /// インメモリ DB でマイグレーション SQL が有効な SQL であること
    func test_migrationSQL_version1_validSQL() throws {
        let db = try openDB(path: ":memory:")
        defer { sqlite3_close(db) }

        let sql = runner.migrationSQL(for: 1)

        // Split by semicolons and execute each statement
        let statements = sql.components(separatedBy: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for statement in statements {
            try executeSQL(db: db, sql: statement + ";")
        }

        let tables = try listTables(db: db)
        XCTAssertTrue(tables.contains("power_samples"))
        XCTAssertTrue(tables.contains("wifi_samples"))
        XCTAssertTrue(tables.contains("daily_rollups"))
        XCTAssertTrue(tables.contains("app_settings"))
        XCTAssertTrue(tables.contains("audit_events"))
        XCTAssertTrue(tables.contains("maintenance_log"))
        XCTAssertTrue(tables.contains("debug_captures"))
    }

    // MARK: - Test Helpers

    private func createEmptyDB() -> String {
        let dbPath = tempDir.appendingPathComponent("test_\(UUID().uuidString).sqlite3").path
        var db: OpaquePointer?
        sqlite3_open(dbPath, &db)
        sqlite3_close(db)
        return dbPath
    }

    private func openDB(path: String) throws -> OpaquePointer {
        var db: OpaquePointer?
        let rc = sqlite3_open(path, &db)
        guard rc == SQLITE_OK, let database = db else {
            throw NSError(domain: "TestDB", code: Int(rc),
                          userInfo: [NSLocalizedDescriptionKey: "Failed to open DB at \(path)"])
        }
        return database
    }

    private func executeSQL(db: OpaquePointer, sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errMsg)
            throw NSError(domain: "TestDB", code: Int(rc),
                          userInfo: [NSLocalizedDescriptionKey: "SQL error: \(msg) for: \(sql)"])
        }
    }


    private func scalarString(db: OpaquePointer, sql: String) throws -> String? {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            throw NSError(domain: "TestDB", code: Int(rc))
        }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW, let cString = sqlite3_column_text(stmt, 0) else {
            return nil
        }
        return String(cString: cString)
    }

    private func listTables(db: OpaquePointer) throws -> [String] {
        var tables: [String] = []
        var stmt: OpaquePointer?
        let sql = "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';"
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            throw NSError(domain: "TestDB", code: Int(rc))
        }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cString = sqlite3_column_text(stmt, 0) {
                tables.append(String(cString: cString))
            }
        }
        return tables
    }
}
