import Foundation
import SQLite3
import os.log

/// マイグレーションランナー (第10.9節)
///
/// PRAGMA user_version でスキーマバージョンを管理し、差分 migration を順次適用する。
/// migration 前に DB ファイルを monitor.sqlite3.bak へコピーする。
/// migration 失敗時は .bak から自動復旧を試みる。
struct MigrationRunner: Sendable {

    /// 現在のコードが期待するスキーマバージョン
    static let targetVersion: Int32 = 2

    /// ロガー
    private static let logger = Logger(subsystem: "com.macusagemeter", category: "MigrationRunner")

    // MARK: - Migration

    /// マイグレーションを実行する (DB ハンドル版)
    ///
    /// 1. 現在の DB user_version を取得
    /// 2. targetVersion と比較
    /// 3. 差分がある場合、.bak を作成してから順次適用
    /// 4. 失敗時は .bak から復旧を試みる
    ///
    /// - Parameters:
    ///   - db: SQLite DB ハンドル
    ///   - dbPath: DB ファイルパス
    /// - Throws: DB-003 (migration 失敗)
    func runMigrations(db: OpaquePointer, dbPath: String) throws {
        let currentVersion = try getCurrentVersion(db: db)
        let target = Self.targetVersion

        if currentVersion >= target {
            Self.logger.info("DB schema is up to date (version=\(currentVersion))")
            return
        }

        Self.logger.info("Migrating DB from version \(currentVersion) to \(target)")

        // バックアップ作成。開いている DB ハンドルから sqlite3_backup API で一貫したコピーを作る。
        do {
            try createBackup(db: db, dbPath: dbPath)
        } catch {
            Self.logger.warning("Backup creation failed: \(error.localizedDescription), proceeding with migration")
        }

        // 差分 migration を順次適用
        for version in (currentVersion + 1)...target {
            let sql = migrationSQL(for: version)
            Self.logger.info("Applying migration v\(version)")

            var errMsg: UnsafeMutablePointer<CChar>?
            let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
            if rc != SQLITE_OK {
                let msg = errMsg.map { String(cString: $0) } ?? "unknown"
                sqlite3_free(errMsg)
                Self.logger.error("Migration v\(version) failed: \(msg)")

                // 復旧試行。開いた DB ハンドルを保持したままファイルを削除せず、backup API で内容を戻す。
                if let restored = try? restoreFromBackup(into: db, dbPath: dbPath), restored {
                    Self.logger.info("Restored open DB handle from backup after migration failure")
                }
                throw DatabaseError.migrationFailed(message: "Migration v\(version) failed: \(msg)")
            }

            // user_version を更新
            let pragmaSQL = "PRAGMA user_version = \(version)"
            let pragmaRc = sqlite3_exec(db, pragmaSQL, nil, nil, nil)
            if pragmaRc != SQLITE_OK {
                Self.logger.error("Failed to set user_version to \(version)")
                if let restored = try? restoreFromBackup(into: db, dbPath: dbPath), restored {
                    Self.logger.info("Restored open DB handle from backup after user_version failure")
                }
                throw DatabaseError.migrationFailed(message: "Failed to set user_version to \(version)")
            }

            Self.logger.info("Migration v\(version) completed successfully")
        }
    }

    /// パスベースのマイグレーション (後方互換)
    func runMigrations(dbPath: String) throws {
        var dbHandle: OpaquePointer?
        let rc = sqlite3_open_v2(dbPath, &dbHandle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard rc == SQLITE_OK, let db = dbHandle else {
            let msg = dbHandle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(dbHandle)
            throw DatabaseError.migrationFailed(message: "Cannot open DB for migration: \(msg)")
        }
        defer { sqlite3_close(db) }
        try runMigrations(db: db, dbPath: dbPath)
    }

    /// 現在の DB user_version を取得する (DB ハンドル版)
    func getCurrentVersion(db: OpaquePointer) throws -> Int32 {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            throw DatabaseError.migrationFailed(message: "Cannot read user_version")
        }
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw DatabaseError.migrationFailed(message: "Cannot read user_version row")
        }
        return sqlite3_column_int(stmt, 0)
    }

    /// 現在の DB user_version を取得する (パスベース)
    func getCurrentVersion(dbPath: String) throws -> Int32 {
        var dbHandle: OpaquePointer?
        let rc = sqlite3_open_v2(dbPath, &dbHandle, SQLITE_OPEN_READONLY, nil)
        guard rc == SQLITE_OK, let db = dbHandle else {
            let msg = dbHandle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(dbHandle)
            throw DatabaseError.migrationFailed(message: "Cannot open DB: \(msg)")
        }
        defer { sqlite3_close(db) }
        return try getCurrentVersion(db: db)
    }

    /// バックアップを作成する (DB ハンドル版)
    ///
    /// 開いている SQLite DB から sqlite3_backup API で一貫したバックアップを作成する。
    /// WAL ファイルを直接コピーしないため、稼働中 DB でも復旧元として安全に扱える。
    func createBackup(db: OpaquePointer, dbPath: String) throws {
        let backupPath = dbPath + ".bak"
        let fm = FileManager.default

        for path in [backupPath, backupPath + "-wal", backupPath + "-shm"] where fm.fileExists(atPath: path) {
            // WAL の自動チェックポイントとの競合で既に消えていることがある。
            try? fm.removeItem(atPath: path)
        }

        var backupDB: OpaquePointer?
        let openRc = sqlite3_open_v2(backupPath, &backupDB, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard openRc == SQLITE_OK, let backupHandle = backupDB else {
            let msg = backupDB.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(backupDB)
            throw DatabaseError.migrationFailed(message: "Cannot open backup DB: \(msg)")
        }
        defer { sqlite3_close(backupHandle) }

        guard let backup = sqlite3_backup_init(backupHandle, "main", db, "main") else {
            let msg = String(cString: sqlite3_errmsg(backupHandle))
            throw DatabaseError.migrationFailed(message: "Cannot initialize DB backup: \(msg)")
        }

        let stepRc = sqlite3_backup_step(backup, -1)
        let finishRc = sqlite3_backup_finish(backup)
        guard stepRc == SQLITE_DONE && finishRc == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(backupHandle))
            throw DatabaseError.migrationFailed(message: "DB backup failed: step=\(stepRc), finish=\(finishRc), \(msg)")
        }
    }

    /// バックアップを作成する
    ///
    /// DB ファイルを monitor.sqlite3.bak にコピーする
    func createBackup(dbPath: String) throws {
        let backupPath = dbPath + ".bak"
        let fm = FileManager.default

        // 既存のバックアップを削除
        if fm.fileExists(atPath: backupPath) {
            try fm.removeItem(atPath: backupPath)
        }

        // WAL ファイルもバックアップ
        try fm.copyItem(atPath: dbPath, toPath: backupPath)

        let walPath = dbPath + "-wal"
        let walBackupPath = backupPath + "-wal"
        if fm.fileExists(atPath: walPath) {
            if fm.fileExists(atPath: walBackupPath) {
                try fm.removeItem(atPath: walBackupPath)
            }
            try fm.copyItem(atPath: walPath, toPath: walBackupPath)
        }

        let shmPath = dbPath + "-shm"
        let shmBackupPath = backupPath + "-shm"
        if fm.fileExists(atPath: shmPath) {
            if fm.fileExists(atPath: shmBackupPath) {
                try fm.removeItem(atPath: shmBackupPath)
            }
            try fm.copyItem(atPath: shmPath, toPath: shmBackupPath)
        }
    }

    /// バックアップから開いている DB ハンドルへ復旧する。
    ///
    /// migration 失敗時に、DB ファイルを削除せず同じ SQLite ハンドルへ内容を戻すために使う。
    func restoreFromBackup(into db: OpaquePointer, dbPath: String) throws -> Bool {
        let backupPath = dbPath + ".bak"
        let fm = FileManager.default

        guard fm.fileExists(atPath: backupPath) else {
            Self.logger.warning("No backup file found at \(backupPath)")
            return false
        }

        var backupDB: OpaquePointer?
        let openRc = sqlite3_open_v2(backupPath, &backupDB, SQLITE_OPEN_READONLY, nil)
        guard openRc == SQLITE_OK, let backupHandle = backupDB else {
            let msg = backupDB.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(backupDB)
            throw DatabaseError.migrationFailed(message: "Cannot open backup DB for restore: \(msg)")
        }
        defer { sqlite3_close(backupHandle) }

        guard let backup = sqlite3_backup_init(db, "main", backupHandle, "main") else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.migrationFailed(message: "Cannot initialize DB restore: \(msg)")
        }

        let stepRc = sqlite3_backup_step(backup, -1)
        let finishRc = sqlite3_backup_finish(backup)
        guard stepRc == SQLITE_DONE && finishRc == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.migrationFailed(message: "DB restore failed: step=\(stepRc), finish=\(finishRc), \(msg)")
        }

        return true
    }

    /// バックアップからの復旧を試みる
    ///
    /// - Parameter dbPath: DB ファイルパス
    /// - Returns: 復旧が成功したかどうか
    func restoreFromBackup(dbPath: String) throws -> Bool {
        let backupPath = dbPath + ".bak"
        let fm = FileManager.default

        guard fm.fileExists(atPath: backupPath) else {
            Self.logger.warning("No backup file found at \(backupPath)")
            return false
        }

        // 現在の DB を削除
        if fm.fileExists(atPath: dbPath) {
            try fm.removeItem(atPath: dbPath)
        }
        // WAL/SHM も削除
        for suffix in ["-wal", "-shm"] {
            let path = dbPath + suffix
            if fm.fileExists(atPath: path) {
                try fm.removeItem(atPath: path)
            }
        }

        // バックアップからコピー
        try fm.copyItem(atPath: backupPath, toPath: dbPath)

        for suffix in ["-wal", "-shm"] {
            let src = backupPath + suffix
            let dst = dbPath + suffix
            if fm.fileExists(atPath: src) {
                try fm.copyItem(atPath: src, toPath: dst)
            }
        }

        Self.logger.info("DB restored from backup")
        return true
    }

    // MARK: - Migration Definitions

    /// バージョンごとの migration SQL を返す
    func migrationSQL(for version: Int32) -> String {
        switch version {
        case 1:
            return Schema.initialDDL
        case 2:
            return """
            CREATE TABLE attributed_usage (
              id                INTEGER PRIMARY KEY AUTOINCREMENT,
              captured_at_ms    INTEGER NOT NULL,
              application_name  TEXT    NOT NULL,
              bundle_identifier TEXT    NULL,
              destination_host  TEXT    NULL,
              sent_bytes        INTEGER NOT NULL DEFAULT 0 CHECK(sent_bytes >= 0),
              received_bytes    INTEGER NOT NULL DEFAULT 0 CHECK(received_bytes >= 0),
              estimated_watts   REAL    NULL
            );
            CREATE INDEX idx_attributed_usage_captured_at ON attributed_usage(captured_at_ms);
            CREATE INDEX idx_attributed_usage_destination ON attributed_usage(application_name, destination_host);
            """
        default:
            preconditionFailure("Unknown migration version: \(version)")
        }
    }
}
