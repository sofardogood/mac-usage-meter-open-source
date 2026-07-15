import Foundation
import SQLite3
import os.log

/// SQLITE_TRANSIENT: SQLite にバインドした文字列を即座にコピーさせる
private let SQLITE_TRANSIENT_VALUE = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// データベースマネージャ (第10章)
///
/// SQLite WAL モードで時系列データ、設定、集計、監査ログを管理する。
/// DB パス: ~/Library/Application Support/<bundle-id>/monitor.sqlite3
/// Collector (writer) と UI (reader) の並行アクセスを WAL モードで許容する。
final class DatabaseManager: @unchecked Sendable {

    /// DB ファイルパス
    let dbPath: String

    /// 現在のスキーマバージョン (PRAGMA user_version)
    static let currentSchemaVersion: Int32 = 2

    /// SQLite DB ハンドル
    private var db: OpaquePointer?

    /// read-only 診断モードフラグ
    private(set) var isReadOnly: Bool = false

    /// 操作の排他制御用ロック
    private let lock = NSLock()

    /// ロガー
    private static let logger = Logger(subsystem: "com.macusagemeter", category: "DatabaseManager")

    // MARK: - Initialization

    /// DatabaseManager を初期化し DB 接続を確立する
    ///
    /// - Parameter dbPath: DB ファイルパス。nil の場合はデフォルトパスを使用
    /// - Throws: DB-001 (DB オープン失敗)
    init(dbPath: String? = nil) throws {
        self.dbPath = dbPath ?? Self.defaultDBPath()
        try openConnection()

        // MigrationRunner でスキーマを最新にする
        let runner = MigrationRunner()
        do {
            try runner.runMigrations(db: self.db!, dbPath: self.dbPath)
        } catch {
            Self.logger.error("Migration failed: \(error.localizedDescription)")
            // migration 失敗時は read-only 診断モード
            isReadOnly = true
        }
    }

    /// Read-only 診断モードで初期化する
    init(dbPath: String, readOnly: Bool) throws {
        self.dbPath = dbPath
        self.isReadOnly = readOnly
        let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        var dbHandle: OpaquePointer?
        let rc = sqlite3_open_v2(dbPath, &dbHandle, flags, nil)
        guard rc == SQLITE_OK, let handle = dbHandle else {
            let msg = dbHandle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(dbHandle)
            throw DatabaseError.openFailed(code: rc, message: msg)
        }
        self.db = handle
        if !readOnly {
            try enableWALMode()
        }
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    /// デフォルトの DB ファイルパスを返す
    ///
    /// `~/Library/Application Support/<bundle-id>/monitor.sqlite3`
    static func defaultDBPath() -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MacUsageMeter")
        return dir.appendingPathComponent("monitor.sqlite3").path
    }

    // MARK: - Power Samples

    /// 電力サンプルを保存する
    func insertPowerSample(_ sample: PowerSample) throws {
        guard !isReadOnly else { throw DatabaseError.readOnlyMode }
        lock.lock()
        defer { lock.unlock() }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_prepare_v2(db, PowerSampleQueries.insert, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw dbError("prepare insertPowerSample") }

        sqlite3_bind_int64(stmt, 1, sample.capturedAtMs)
        if let watts = sample.avgWatts {
            sqlite3_bind_double(stmt, 2, watts)
        } else {
            sqlite3_bind_null(stmt, 2)
        }
        sqlite3_bind_double(stmt, 3, sample.sampleDurationSec)
        sqlite3_bind_text(stmt, 4, (sample.sourceLevel.rawValue as NSString).utf8String, -1, SQLITE_TRANSIENT_VALUE)
        sqlite3_bind_text(stmt, 5, (sample.status.rawValue as NSString).utf8String, -1, SQLITE_TRANSIENT_VALUE)
        sqlite3_bind_text(stmt, 6, (sample.parserStatus.rawValue as NSString).utf8String, -1, SQLITE_TRANSIENT_VALUE)
        sqlite3_bind_int(stmt, 7, Int32(sample.outlierFlag))
        bindOptionalText(stmt, index: 8, value: sample.rawCaptureId)
        bindOptionalText(stmt, index: 9, value: sample.errorCode)

        guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError("step insertPowerSample") }
    }

    /// 指定期間の電力サンプルを取得する
    func fetchPowerSamples(fromMs: Int64, toMs: Int64) throws -> [PowerSample] {
        lock.lock()
        defer { lock.unlock() }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_prepare_v2(db, PowerSampleQueries.fetchByRange, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw dbError("prepare fetchPowerSamples") }

        sqlite3_bind_int64(stmt, 1, fromMs)
        sqlite3_bind_int64(stmt, 2, toMs)

        var samples: [PowerSample] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            samples.append(readPowerSample(stmt))
        }
        return samples
    }

    /// 最新の電力サンプルを取得する
    func fetchLatestPowerSample() throws -> PowerSample? {
        lock.lock()
        defer { lock.unlock() }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_prepare_v2(db, PowerSampleQueries.fetchLatest, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw dbError("prepare fetchLatestPowerSample") }

        if sqlite3_step(stmt) == SQLITE_ROW {
            return readPowerSample(stmt)
        }
        return nil
    }

    /// 最新の成功した電力サンプルを取得する (avg_watts が NOT NULL)
    func fetchLatestSuccessPowerSample() throws -> PowerSample? {
        lock.lock()
        defer { lock.unlock() }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_prepare_v2(db, PowerSampleQueries.fetchLatestSuccess, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw dbError("prepare fetchLatestSuccessPowerSample") }

        if sqlite3_step(stmt) == SQLITE_ROW {
            return readPowerSample(stmt)
        }
        return nil
    }

    // MARK: - Wi-Fi Samples

    /// Wi-Fi サンプルを保存する
    func insertWifiSample(_ sample: WifiSample) throws {
        guard !isReadOnly else { throw DatabaseError.readOnlyMode }
        lock.lock()
        defer { lock.unlock() }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_prepare_v2(db, WifiSampleQueries.insert, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw dbError("prepare insertWifiSample") }

        sqlite3_bind_int64(stmt, 1, sample.capturedAtMs)
        sqlite3_bind_text(stmt, 2, (sample.interfaceName as NSString).utf8String, -1, SQLITE_TRANSIENT_VALUE)
        sqlite3_bind_int64(stmt, 3, sample.sentBytesTotal)
        sqlite3_bind_int64(stmt, 4, sample.recvBytesTotal)
        sqlite3_bind_int64(stmt, 5, sample.sentBytesDelta)
        sqlite3_bind_int64(stmt, 6, sample.recvBytesDelta)
        sqlite3_bind_int(stmt, 7, Int32(sample.counterResetFlag))
        sqlite3_bind_text(stmt, 8, (sample.status.rawValue as NSString).utf8String, -1, SQLITE_TRANSIENT_VALUE)
        bindOptionalText(stmt, index: 9, value: sample.errorCode)

        guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError("step insertWifiSample") }
    }

    /// 指定期間の Wi-Fi 使用量合計 (bytes) を取得する (高速集計)
    func sumWifiBytes(fromMs: Int64, toMs: Int64) throws -> Int64 {
        lock.lock()
        defer { lock.unlock() }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_prepare_v2(db, WifiSampleQueries.dailyTotalBytes, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw dbError("prepare sumWifiBytes") }

        sqlite3_bind_int64(stmt, 1, fromMs)
        sqlite3_bind_int64(stmt, 2, toMs)

        if sqlite3_step(stmt) == SQLITE_ROW {
            return sqlite3_column_int64(stmt, 0)
        }
        return 0
    }

    /// 指定期間の電力量合計 (kWh) を取得する (高速集計)
    func sumPowerKwh(fromMs: Int64, toMs: Int64) throws -> Double {
        lock.lock()
        defer { lock.unlock() }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_prepare_v2(db, PowerSampleQueries.sumWattSeconds, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw dbError("prepare sumPowerKwh") }

        sqlite3_bind_int64(stmt, 1, fromMs)
        sqlite3_bind_int64(stmt, 2, toMs)

        if sqlite3_step(stmt) == SQLITE_ROW {
            return sqlite3_column_double(stmt, 0) / 3_600_000.0
        }
        return 0.0
    }

    /// 指定期間の Wi-Fi サンプルを取得する
    func fetchWifiSamples(fromMs: Int64, toMs: Int64) throws -> [WifiSample] {
        lock.lock()
        defer { lock.unlock() }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_prepare_v2(db, WifiSampleQueries.fetchByRange, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw dbError("prepare fetchWifiSamples") }

        sqlite3_bind_int64(stmt, 1, fromMs)
        sqlite3_bind_int64(stmt, 2, toMs)

        var samples: [WifiSample] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            samples.append(readWifiSample(stmt))
        }
        return samples
    }

    /// 最新の Wi-Fi サンプルを取得する
    func fetchLatestWifiSample() throws -> WifiSample? {
        lock.lock()
        defer { lock.unlock() }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_prepare_v2(db, WifiSampleQueries.fetchLatest, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw dbError("prepare fetchLatestWifiSample") }

        if sqlite3_step(stmt) == SQLITE_ROW {
            return readWifiSample(stmt)
        }
        return nil
    }

    /// 当日の Wi-Fi 使用量合計 (bytes) を取得する
    func fetchDailyWifiTotalBytes(fromMs: Int64, toMs: Int64) throws -> Int64 {
        lock.lock()
        defer { lock.unlock() }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_prepare_v2(db, WifiSampleQueries.dailyTotalBytes, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw dbError("prepare fetchDailyWifiTotalBytes") }

        sqlite3_bind_int64(stmt, 1, fromMs)
        sqlite3_bind_int64(stmt, 2, toMs)

        if sqlite3_step(stmt) == SQLITE_ROW {
            return sqlite3_column_int64(stmt, 0)
        }
        return 0
    }

    // MARK: - Attributed Usage

    /// Network Extension が観測したアプリ・宛先別の通信量を保存する。
    func insertAttributedUsage(_ usage: AttributedUsage) throws {
        guard !isReadOnly else { throw DatabaseError.readOnlyMode }
        lock.lock()
        defer { lock.unlock() }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_prepare_v2(db, AttributedUsageQueries.insert, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw dbError("prepare insertAttributedUsage") }

        sqlite3_bind_int64(stmt, 1, usage.capturedAtMs)
        sqlite3_bind_text(stmt, 2, (usage.applicationName as NSString).utf8String, -1, SQLITE_TRANSIENT_VALUE)
        bindOptionalText(stmt, index: 3, value: usage.bundleIdentifier)
        bindOptionalText(stmt, index: 4, value: usage.destinationHost)
        sqlite3_bind_int64(stmt, 5, usage.sentBytes)
        sqlite3_bind_int64(stmt, 6, usage.receivedBytes)
        bindOptionalDouble(stmt, index: 7, value: usage.estimatedWatts)

        guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError("step insertAttributedUsage") }
    }

    /// 指定期間のアプリ・宛先別通信量を、使用量の多い順で取得する。
    func fetchUsageDestinationSummaries(fromMs: Int64, toMs: Int64) throws -> [UsageDestinationSummary] {
        lock.lock()
        defer { lock.unlock() }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_prepare_v2(db, AttributedUsageQueries.summaryByDestination, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw dbError("prepare fetchUsageDestinationSummaries") }

        sqlite3_bind_int64(stmt, 1, fromMs)
        sqlite3_bind_int64(stmt, 2, toMs)

        var summaries: [UsageDestinationSummary] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let watts: Double? = sqlite3_column_type(stmt, 4) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 4)
            summaries.append(UsageDestinationSummary(
                applicationName: columnText(stmt, 0),
                bundleIdentifier: sqlite3_column_type(stmt, 1) == SQLITE_NULL ? nil : columnText(stmt, 1),
                destinationHost: sqlite3_column_type(stmt, 2) == SQLITE_NULL ? nil : columnText(stmt, 2),
                totalBytes: sqlite3_column_int64(stmt, 3),
                estimatedWatts: watts
            ))
        }
        return summaries
    }

    // MARK: - Daily Rollups

    /// 日次ロールアップを保存する (INSERT OR REPLACE)
    func upsertDailyRollup(_ rollup: DailyRollup) throws {
        guard !isReadOnly else { throw DatabaseError.readOnlyMode }
        lock.lock()
        defer { lock.unlock() }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_prepare_v2(db, DailyRollupQueries.upsert, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw dbError("prepare upsertDailyRollup") }

        sqlite3_bind_text(stmt, 1, (rollup.dateLocal as NSString).utf8String, -1, SQLITE_TRANSIENT_VALUE)
        bindOptionalDouble(stmt, index: 2, value: rollup.powerKwh)
        bindOptionalDouble(stmt, index: 3, value: rollup.wifiGb)
        bindOptionalDouble(stmt, index: 4, value: rollup.powerCostYen)
        bindOptionalDouble(stmt, index: 5, value: rollup.networkCostYen)
        sqlite3_bind_double(stmt, 6, rollup.coverageRatioPower)
        sqlite3_bind_double(stmt, 7, rollup.coverageRatioWifi)
        sqlite3_bind_int(stmt, 8, Int32(rollup.sampleCountPower))
        sqlite3_bind_int(stmt, 9, Int32(rollup.sampleCountWifi))
        sqlite3_bind_int64(stmt, 10, rollup.computedAtMs)

        guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError("step upsertDailyRollup") }
    }

    /// 指定期間の日次ロールアップを取得する
    func fetchDailyRollups(fromDate: String, toDate: String) throws -> [DailyRollup] {
        lock.lock()
        defer { lock.unlock() }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_prepare_v2(db, DailyRollupQueries.fetchByRange, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw dbError("prepare fetchDailyRollups") }

        sqlite3_bind_text(stmt, 1, (fromDate as NSString).utf8String, -1, SQLITE_TRANSIENT_VALUE)
        sqlite3_bind_text(stmt, 2, (toDate as NSString).utf8String, -1, SQLITE_TRANSIENT_VALUE)

        var rollups: [DailyRollup] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rollups.append(readDailyRollup(stmt))
        }
        return rollups
    }

    /// 月次電力料金合計を取得する
    func fetchMonthlyPowerCost(fromDate: String, toDate: String) throws -> Double {
        lock.lock()
        defer { lock.unlock() }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_prepare_v2(db, DailyRollupQueries.monthlyPowerCost, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw dbError("prepare fetchMonthlyPowerCost") }

        sqlite3_bind_text(stmt, 1, (fromDate as NSString).utf8String, -1, SQLITE_TRANSIENT_VALUE)
        sqlite3_bind_text(stmt, 2, (toDate as NSString).utf8String, -1, SQLITE_TRANSIENT_VALUE)

        if sqlite3_step(stmt) == SQLITE_ROW && sqlite3_column_type(stmt, 0) != SQLITE_NULL {
            return sqlite3_column_double(stmt, 0)
        }
        return 0.0
    }

    /// 月次 Wi-Fi 累計 GB を取得する
    func fetchMonthlyWifiGb(fromDate: String, toDate: String) throws -> Double {
        lock.lock()
        defer { lock.unlock() }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_prepare_v2(db, DailyRollupQueries.monthlyWifiGb, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw dbError("prepare fetchMonthlyWifiGb") }

        sqlite3_bind_text(stmt, 1, (fromDate as NSString).utf8String, -1, SQLITE_TRANSIENT_VALUE)
        sqlite3_bind_text(stmt, 2, (toDate as NSString).utf8String, -1, SQLITE_TRANSIENT_VALUE)

        if sqlite3_step(stmt) == SQLITE_ROW && sqlite3_column_type(stmt, 0) != SQLITE_NULL {
            return sqlite3_column_double(stmt, 0)
        }
        return 0.0
    }

    /// 月次電力量 (kWh) を合算する
    func fetchMonthlyPowerKwh(fromDate: String, toDate: String) throws -> Double {
        lock.lock()
        defer { lock.unlock() }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_prepare_v2(db, DailyRollupQueries.monthlyPowerKwh, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw dbError("prepare fetchMonthlyPowerKwh") }

        sqlite3_bind_text(stmt, 1, (fromDate as NSString).utf8String, -1, SQLITE_TRANSIENT_VALUE)
        sqlite3_bind_text(stmt, 2, (toDate as NSString).utf8String, -1, SQLITE_TRANSIENT_VALUE)

        if sqlite3_step(stmt) == SQLITE_ROW && sqlite3_column_type(stmt, 0) != SQLITE_NULL {
            return sqlite3_column_double(stmt, 0)
        }
        return 0.0
    }

    /// 月次通信料金合計を取得する (fixed モデル用)
    func fetchMonthlyNetworkCost(fromDate: String, toDate: String) throws -> Double {
        lock.lock()
        defer { lock.unlock() }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_prepare_v2(db, DailyRollupQueries.monthlyNetworkCost, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw dbError("prepare fetchMonthlyNetworkCost") }

        sqlite3_bind_text(stmt, 1, (fromDate as NSString).utf8String, -1, SQLITE_TRANSIENT_VALUE)
        sqlite3_bind_text(stmt, 2, (toDate as NSString).utf8String, -1, SQLITE_TRANSIENT_VALUE)

        if sqlite3_step(stmt) == SQLITE_ROW && sqlite3_column_type(stmt, 0) != SQLITE_NULL {
            return sqlite3_column_double(stmt, 0)
        }
        return 0.0
    }

    /// 全ロールアップの日付一覧を取得する
    func fetchAllDailyRollupDates() throws -> [String] {
        lock.lock()
        defer { lock.unlock() }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_prepare_v2(db, DailyRollupQueries.fetchAllDates, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw dbError("prepare fetchAllDailyRollupDates") }

        var dates: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cStr = sqlite3_column_text(stmt, 0) {
                dates.append(String(cString: cStr))
            }
        }
        return dates
    }

    /// サンプル (電力 + Wi-Fi) が存在する全日付を取得する
    func fetchAllSampleDates() throws -> [String] {
        lock.lock()
        defer { lock.unlock() }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_prepare_v2(db, DailyRollupQueries.fetchAllSampleDates, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw dbError("prepare fetchAllSampleDates") }

        var dates: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cStr = sqlite3_column_text(stmt, 0) {
                dates.append(String(cString: cStr))
            }
        }
        return dates
    }

    // MARK: - App Settings

    /// 設定を保存する
    func upsertSetting(_ setting: AppSetting) throws {
        guard !isReadOnly else { throw DatabaseError.readOnlyMode }
        lock.lock()
        defer { lock.unlock() }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_prepare_v2(db, SettingsQueries.upsert, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw dbError("prepare upsertSetting") }

        sqlite3_bind_text(stmt, 1, (setting.key as NSString).utf8String, -1, SQLITE_TRANSIENT_VALUE)
        bindOptionalText(stmt, index: 2, value: setting.valueText)
        bindOptionalDouble(stmt, index: 3, value: setting.valueNumber)
        if let b = setting.valueBool {
            sqlite3_bind_int(stmt, 4, Int32(b))
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        sqlite3_bind_int64(stmt, 5, setting.updatedAtMs)

        guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError("step upsertSetting") }
    }

    /// 設定を取得する
    func fetchSetting(key: String) throws -> AppSetting? {
        lock.lock()
        defer { lock.unlock() }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_prepare_v2(db, SettingsQueries.fetchByKey, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw dbError("prepare fetchSetting") }

        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, SQLITE_TRANSIENT_VALUE)

        if sqlite3_step(stmt) == SQLITE_ROW {
            return readAppSetting(stmt)
        }
        return nil
    }

    /// 全設定を取得する
    func fetchAllSettings() throws -> [AppSetting] {
        lock.lock()
        defer { lock.unlock() }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_prepare_v2(db, SettingsQueries.fetchAll, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw dbError("prepare fetchAllSettings") }

        var settings: [AppSetting] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            settings.append(readAppSetting(stmt))
        }
        return settings
    }

    // MARK: - Audit Events

    /// 監査イベントを記録する
    func insertAuditEvent(_ event: AuditEvent) throws {
        guard !isReadOnly else { throw DatabaseError.readOnlyMode }
        lock.lock()
        defer { lock.unlock() }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_prepare_v2(db, AuditEventQueries.insert, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw dbError("prepare insertAuditEvent") }

        sqlite3_bind_int64(stmt, 1, event.occurredAtMs)
        sqlite3_bind_text(stmt, 2, (event.eventType.rawValue as NSString).utf8String, -1, SQLITE_TRANSIENT_VALUE)
        sqlite3_bind_text(stmt, 3, (event.severity.rawValue as NSString).utf8String, -1, SQLITE_TRANSIENT_VALUE)
        sqlite3_bind_text(stmt, 4, (event.component as NSString).utf8String, -1, SQLITE_TRANSIENT_VALUE)
        bindOptionalText(stmt, index: 5, value: event.errorCode)
        bindOptionalText(stmt, index: 6, value: event.detailJson)

        guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError("step insertAuditEvent") }
    }

    // MARK: - Maintenance Log

    /// メンテナンスログを記録する
    func insertMaintenanceLog(ranAtMs: Int64, jobName: String, result: String, deletedRows: Int, notes: String?) throws {
        guard !isReadOnly else { throw DatabaseError.readOnlyMode }
        lock.lock()
        defer { lock.unlock() }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_prepare_v2(db, MaintenanceLogQueries.insert, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw dbError("prepare insertMaintenanceLog") }

        sqlite3_bind_int64(stmt, 1, ranAtMs)
        sqlite3_bind_text(stmt, 2, (jobName as NSString).utf8String, -1, SQLITE_TRANSIENT_VALUE)
        sqlite3_bind_text(stmt, 3, (result as NSString).utf8String, -1, SQLITE_TRANSIENT_VALUE)
        sqlite3_bind_int(stmt, 4, Int32(deletedRows))
        bindOptionalText(stmt, index: 5, value: notes)

        guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError("step insertMaintenanceLog") }
    }

    /// 最新のメンテナンスログを取得する
    func fetchLatestMaintenanceLog(jobName: String) throws -> (ranAtMs: Int64, deletedRows: Int)? {
        lock.lock()
        defer { lock.unlock() }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_prepare_v2(db, MaintenanceLogQueries.fetchLatestByJob, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw dbError("prepare fetchLatestMaintenanceLog") }

        sqlite3_bind_text(stmt, 1, (jobName as NSString).utf8String, -1, SQLITE_TRANSIENT_VALUE)

        if sqlite3_step(stmt) == SQLITE_ROW {
            let ranAtMs = sqlite3_column_int64(stmt, 1)
            let deletedRows = Int(sqlite3_column_int(stmt, 4))
            return (ranAtMs: ranAtMs, deletedRows: deletedRows)
        }
        return nil
    }

    // MARK: - Debug Captures

    /// デバッグキャプチャを保存する
    func insertDebugCapture(id: String, capturedAtMs: Int64, command: String, rawStdout: String?, rawStderr: String?, exitCode: Int32?, relatedSampleId: Int64?) throws {
        guard !isReadOnly else { throw DatabaseError.readOnlyMode }
        lock.lock()
        defer { lock.unlock() }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_prepare_v2(db, DebugCaptureQueries.insert, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw dbError("prepare insertDebugCapture") }

        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, SQLITE_TRANSIENT_VALUE)
        sqlite3_bind_int64(stmt, 2, capturedAtMs)
        sqlite3_bind_text(stmt, 3, (command as NSString).utf8String, -1, SQLITE_TRANSIENT_VALUE)
        bindOptionalText(stmt, index: 4, value: rawStdout)
        bindOptionalText(stmt, index: 5, value: rawStderr)
        if let code = exitCode {
            sqlite3_bind_int(stmt, 6, code)
        } else {
            sqlite3_bind_null(stmt, 6)
        }
        if let sampleId = relatedSampleId {
            sqlite3_bind_int64(stmt, 7, sampleId)
        } else {
            sqlite3_bind_null(stmt, 7)
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError("step insertDebugCapture") }
    }

    // MARK: - Maintenance

    /// パージを実行する
    ///
    /// - Parameter retentionDays: 保持日数
    /// - Returns: 削除行数
    func purge(retentionDays: Int) throws -> Int {
        guard !isReadOnly else { throw DatabaseError.readOnlyMode }

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let msPerDay: Int64 = 86_400_000

        // power_samples / wifi_samples: retentionDays
        let sampleCutoff = now - Int64(retentionDays) * msPerDay
        // daily_rollups: 365日
        let rollupCutoffDate = Calendar.current.date(byAdding: .day, value: -365, to: Date())!
        let rollupDateFormatter = DateFormatter()
        rollupDateFormatter.dateFormat = "yyyy-MM-dd"
        rollupDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        let rollupCutoff = rollupDateFormatter.string(from: rollupCutoffDate)
        // audit_events: 180日 (error は365日)
        let auditCutoff = now - 180 * msPerDay
        let auditErrorCutoff = now - 365 * msPerDay
        // debug_captures: 7日
        let debugCutoff = now - 7 * msPerDay

        var totalDeleted = 0

        lock.lock()
        defer { lock.unlock() }

        // power_samples
        totalDeleted += try executePurge(PowerSampleQueries.purge, bindings: [.int64(sampleCutoff)])
        // wifi_samples
        totalDeleted += try executePurge(WifiSampleQueries.purge, bindings: [.int64(sampleCutoff)])
        totalDeleted += try executePurge(AttributedUsageQueries.purge, bindings: [.int64(sampleCutoff)])
        // daily_rollups
        totalDeleted += try executePurge(DailyRollupQueries.purge, bindings: [.text(rollupCutoff)])
        // audit_events (2つのバインド: 通常 180日、error 365日)
        totalDeleted += try executePurgeAuditEvents(normalCutoff: auditCutoff, errorCutoff: auditErrorCutoff)
        // debug_captures
        totalDeleted += try executePurge(DebugCaptureQueries.purge, bindings: [.int64(debugCutoff)])

        return totalDeleted
    }

    /// VACUUM を実行する
    ///
    /// 条件: 前回 VACUUM から 7 日以上経過かつ累計削除行数 > 10,000 行
    func vacuumIfNeeded() throws {
        guard !isReadOnly else { return }

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let sevenDaysMs: Int64 = 7 * 86_400_000

        if let lastVacuum = try? fetchLatestMaintenanceLog(jobName: "vacuum") {
            if now - lastVacuum.ranAtMs < sevenDaysMs { return }
        }

        // 累計削除行数を purge ログから集計
        // 簡略化: purge 後に呼ばれる前提なので、直近の purge deletedRows を確認
        if let lastPurge = try? fetchLatestMaintenanceLog(jobName: "purge") {
            if lastPurge.deletedRows <= 10_000 { return }
        } else {
            return
        }

        // VACUUM を排他実行 (insertMaintenanceLog も lock を取るため、
        // VACUUM 実行のスコープだけで lock を保持し、ログ記録は外で行う)
        let vacuumSucceeded: Bool
        lock.lock()
        let rc = sqlite3_exec(db, "VACUUM", nil, nil, nil)
        vacuumSucceeded = (rc == SQLITE_OK)
        lock.unlock()

        if vacuumSucceeded {
            try? insertMaintenanceLog(ranAtMs: now, jobName: "vacuum", result: "success", deletedRows: 0, notes: nil)
        }
    }

    // MARK: - Raw SQL Execution (for MigrationRunner)

    /// 複数の SQL 文を実行する (migration 用)
    func executeStatements(_ sql: String) throws {
        lock.lock()
        defer { lock.unlock() }

        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errMsg)
            throw DatabaseError.executionFailed(code: rc, message: msg)
        }
    }

    /// user_version を取得する
    func getUserVersion() throws -> Int32 {
        lock.lock()
        defer { lock.unlock() }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw dbError("prepare getUserVersion") }

        guard sqlite3_step(stmt) == SQLITE_ROW else { throw dbError("step getUserVersion") }
        return sqlite3_column_int(stmt, 0)
    }

    /// user_version を設定する
    func setUserVersion(_ version: Int32) throws {
        lock.lock()
        defer { lock.unlock() }

        let sql = "PRAGMA user_version = \(version)"
        let rc = sqlite3_exec(db, sql, nil, nil, nil)
        guard rc == SQLITE_OK else { throw dbError("exec setUserVersion") }
    }

    // MARK: - Private

    /// DB 接続を開く (WAL モード)
    private func openConnection() throws {
        // ディレクトリ作成
        let dirPath = (dbPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true)

        // ディレクトリパーミッション 0700
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dirPath)

        var dbHandle: OpaquePointer?
        let rc = sqlite3_open_v2(dbPath, &dbHandle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard rc == SQLITE_OK, let handle = dbHandle else {
            let msg = dbHandle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(dbHandle)
            throw DatabaseError.openFailed(code: rc, message: msg)
        }
        self.db = handle

        // DB ファイルパーミッション 0600
        if FileManager.default.fileExists(atPath: dbPath) {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dbPath)
        }

        try enableWALMode()
    }

    private func enableWALMode() throws {
        let rc = sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil)
        guard rc == SQLITE_OK else {
            throw DatabaseError.executionFailed(code: rc, message: "Failed to enable WAL mode")
        }
    }

    private func dbError(_ context: String) -> DatabaseError {
        let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
        let code = db.flatMap { sqlite3_errcode($0) } ?? -1
        return .executionFailed(code: code, message: "\(context): \(msg)")
    }

    // MARK: - Bind Helpers

    private func bindOptionalText(_ stmt: OpaquePointer?, index: Int32, value: String?) {
        if let v = value {
            sqlite3_bind_text(stmt, index, (v as NSString).utf8String, -1, SQLITE_TRANSIENT_VALUE)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bindOptionalDouble(_ stmt: OpaquePointer?, index: Int32, value: Double?) {
        if let v = value {
            sqlite3_bind_double(stmt, index, v)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    // MARK: - Row Readers

    private func readPowerSample(_ stmt: OpaquePointer?) -> PowerSample {
        let id = sqlite3_column_int64(stmt, 0)
        let capturedAtMs = sqlite3_column_int64(stmt, 1)
        let avgWatts: Double? = sqlite3_column_type(stmt, 2) != SQLITE_NULL ? sqlite3_column_double(stmt, 2) : nil
        let sampleDurationSec = sqlite3_column_double(stmt, 3)
        let sourceLevel = PowerSample.SourceLevel(rawValue: columnText(stmt, 4)) ?? .c
        let status = PowerSample.SampleStatus(rawValue: columnText(stmt, 5)) ?? .fail
        let parserStatus = PowerSample.ParserStatus(rawValue: columnText(stmt, 6)) ?? .fail
        let outlierFlag = Int(sqlite3_column_int(stmt, 7))
        let rawCaptureId: String? = sqlite3_column_type(stmt, 8) != SQLITE_NULL ? columnText(stmt, 8) : nil
        let errorCode: String? = sqlite3_column_type(stmt, 9) != SQLITE_NULL ? columnText(stmt, 9) : nil

        return PowerSample(
            id: id, capturedAtMs: capturedAtMs, avgWatts: avgWatts,
            sampleDurationSec: sampleDurationSec, sourceLevel: sourceLevel,
            status: status, parserStatus: parserStatus, outlierFlag: outlierFlag,
            rawCaptureId: rawCaptureId, errorCode: errorCode
        )
    }

    private func readWifiSample(_ stmt: OpaquePointer?) -> WifiSample {
        let id = sqlite3_column_int64(stmt, 0)
        let capturedAtMs = sqlite3_column_int64(stmt, 1)
        let interfaceName = columnText(stmt, 2)
        let sentBytesTotal = sqlite3_column_int64(stmt, 3)
        let recvBytesTotal = sqlite3_column_int64(stmt, 4)
        let sentBytesDelta = sqlite3_column_int64(stmt, 5)
        let recvBytesDelta = sqlite3_column_int64(stmt, 6)
        let counterResetFlag = Int(sqlite3_column_int(stmt, 7))
        let status = WifiSample.WifiSampleStatus(rawValue: columnText(stmt, 8)) ?? .fail
        let errorCode: String? = sqlite3_column_type(stmt, 9) != SQLITE_NULL ? columnText(stmt, 9) : nil

        return WifiSample(
            id: id, capturedAtMs: capturedAtMs, interfaceName: interfaceName,
            sentBytesTotal: sentBytesTotal, recvBytesTotal: recvBytesTotal,
            sentBytesDelta: sentBytesDelta, recvBytesDelta: recvBytesDelta,
            counterResetFlag: counterResetFlag, status: status, errorCode: errorCode
        )
    }

    private func readDailyRollup(_ stmt: OpaquePointer?) -> DailyRollup {
        let dateLocal = columnText(stmt, 0)
        let powerKwh: Double? = sqlite3_column_type(stmt, 1) != SQLITE_NULL ? sqlite3_column_double(stmt, 1) : nil
        let wifiGb: Double? = sqlite3_column_type(stmt, 2) != SQLITE_NULL ? sqlite3_column_double(stmt, 2) : nil
        let powerCostYen: Double? = sqlite3_column_type(stmt, 3) != SQLITE_NULL ? sqlite3_column_double(stmt, 3) : nil
        let networkCostYen: Double? = sqlite3_column_type(stmt, 4) != SQLITE_NULL ? sqlite3_column_double(stmt, 4) : nil
        let coverageRatioPower = sqlite3_column_double(stmt, 5)
        let coverageRatioWifi = sqlite3_column_double(stmt, 6)
        let sampleCountPower = Int(sqlite3_column_int(stmt, 7))
        let sampleCountWifi = Int(sqlite3_column_int(stmt, 8))
        let computedAtMs = sqlite3_column_int64(stmt, 9)

        return DailyRollup(
            dateLocal: dateLocal, powerKwh: powerKwh, wifiGb: wifiGb,
            powerCostYen: powerCostYen, networkCostYen: networkCostYen,
            coverageRatioPower: coverageRatioPower, coverageRatioWifi: coverageRatioWifi,
            sampleCountPower: sampleCountPower, sampleCountWifi: sampleCountWifi,
            computedAtMs: computedAtMs
        )
    }

    private func readAppSetting(_ stmt: OpaquePointer?) -> AppSetting {
        let key = columnText(stmt, 0)
        let valueText: String? = sqlite3_column_type(stmt, 1) != SQLITE_NULL ? columnText(stmt, 1) : nil
        let valueNumber: Double? = sqlite3_column_type(stmt, 2) != SQLITE_NULL ? sqlite3_column_double(stmt, 2) : nil
        let valueBool: Int? = sqlite3_column_type(stmt, 3) != SQLITE_NULL ? Int(sqlite3_column_int(stmt, 3)) : nil
        let updatedAtMs = sqlite3_column_int64(stmt, 4)

        return AppSetting(key: key, valueText: valueText, valueNumber: valueNumber, valueBool: valueBool, updatedAtMs: updatedAtMs)
    }

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let cStr = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: cStr)
    }

    // MARK: - Purge Helpers

    private enum BindValue {
        case int64(Int64)
        case text(String)
    }

    private func executePurge(_ sql: String, bindings: [BindValue]) throws -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw dbError("prepare purge") }

        for (i, binding) in bindings.enumerated() {
            let idx = Int32(i + 1)
            switch binding {
            case .int64(let v):
                sqlite3_bind_int64(stmt, idx, v)
            case .text(let v):
                sqlite3_bind_text(stmt, idx, (v as NSString).utf8String, -1, SQLITE_TRANSIENT_VALUE)
            }
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError("step purge") }
        return Int(sqlite3_changes(db))
    }

    private func executePurgeAuditEvents(normalCutoff: Int64, errorCutoff: Int64) throws -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_prepare_v2(db, AuditEventQueries.purge, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw dbError("prepare purgeAuditEvents") }

        sqlite3_bind_int64(stmt, 1, normalCutoff)
        sqlite3_bind_int64(stmt, 2, errorCutoff)

        guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError("step purgeAuditEvents") }
        return Int(sqlite3_changes(db))
    }
}

// MARK: - Database Error

enum DatabaseError: Error, LocalizedError {
    case openFailed(code: Int32, message: String)
    case executionFailed(code: Int32, message: String)
    case readOnlyMode
    case migrationFailed(message: String)
    case backupFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let code, let msg):
            return "DB-001: DB open failed (code=\(code)): \(msg)"
        case .executionFailed(let code, let msg):
            return "DB-002: Execution failed (code=\(code)): \(msg)"
        case .readOnlyMode:
            return "DB: Read-only diagnostic mode"
        case .migrationFailed(let msg):
            return "DB-003: Migration failed: \(msg)"
        case .backupFailed(let msg):
            return "DB: Backup failed: \(msg)"
        }
    }
}
