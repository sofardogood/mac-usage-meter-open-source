import Foundation
import Darwin
import os.log
import CoreWLAN

/// Collector Controller - サンプリングのスケジューリングと状態管理 (第2.1節)
///
/// UI App プロセス内で動作する Swift actor。
/// タイマー制御、XPC 呼び出し、状態遷移、DB 保存、ロールアップ開始を担当する。
actor CollectorController {

    // MARK: - Properties

    /// 現在の Collector 状態
    private(set) var state: CollectorState = .starting

    /// 連続失敗回数
    private var consecutiveFailureCount: Int = 0

    /// 最終成功時刻 (UTC Epoch ms) - 後方互換用
    private var lastSuccessAtMs: Int64?

    /// 電力の最終成功時刻 (UTC Epoch ms) - stale 検出用
    private var lastPowerSuccessAtMs: Int64?

    /// Wi-Fi の最終成功時刻 (UTC Epoch ms) - stale 検出用
    private var lastWifiSuccessAtMs: Int64?

    /// 現在 stale 状態にあるかどうか (電力)
    private(set) var isPowerStale: Bool = false

    /// 現在 stale 状態にあるかどうか (Wi-Fi)
    private(set) var isWifiStale: Bool = false

    /// 最新の電力サンプル (メモリキャッシュ)
    private var latestPowerSample: PowerSample?

    /// 最新の Wi-Fi サンプル (メモリキャッシュ)
    private var latestWifiSample: WifiSample?

    /// 電力サンプルのメモリキャッシュ (DB書込み失敗時の退避用、上限1000件)
    private var powerSampleCache: [PowerSample] = []

    /// Wi-Fi サンプルのメモリキャッシュ (DB書込み失敗時の退避用、上限1000件)
    private var wifiSampleCache: [WifiSample] = []

    /// `nettop` の接続別累積カウンタ。アプリ・宛先別の差分計算に使う。
    private var previousAttributedFlows: [String: ProcessNetworkUsageReader.Flow] = [:]

    /// 前回の Wi-Fi カウンタ (差分計算用)
    private var previousWifiSnapshot: WifiSnapshotResponse?

    /// XPC クライアント
    private let xpcClient: XPCClient

    /// データベースマネージャ
    private let databaseManager: DatabaseManager

    /// 電力採取間隔 (秒)
    private var powerSamplingIntervalSec: Int

    /// Wi-Fi 採取間隔 (秒)
    private var wifiSamplingIntervalSec: Int

    /// 保持期間 (日)
    private var retentionDays: Int = 90

    /// 電力採取タスク
    private var powerTask: Task<Void, Never>?

    /// Wi-Fi 採取タスク
    private var wifiTask: Task<Void, Never>?

    private var attributedUsageTask: Task<Void, Never>?

    /// ロールアップ・パージタスク
    private var maintenanceTask: Task<Void, Never>?

    /// 当日ロールアップ定期更新タスク (60秒ごと)
    private var todayRollupTask: Task<Void, Never>?

    /// Helper 復帰監視タスク
    private var helperRecoveryTask: Task<Void, Never>?

    /// Collector が起動中かどうか
    private var isRunning: Bool = false

    /// 当日ロールアップの最終実行時刻
    private var lastTodayRollupAtMs: Int64?

    /// 能力検出結果
    private var capabilities: CapabilitiesResponse?

    /// プロファイル ID
    private var activeProfileId: String?

    /// デバッグ採取有効フラグ
    private var debugCaptureEnabled: Bool = false

    /// バックオフ中の電力採取間隔 (秒)
    private var currentPowerInterval: Int

    /// メモリキャッシュ上限
    private static let cacheLimit = 1000

    /// ロガー
    private static let logger = Logger(subsystem: "com.macusagemeter", category: "CollectorController")

    /// ロールアップ計算器
    private let rollupCalculator = RollupCalculator()

    // MARK: - Initialization

    /// Collector Controller を初期化する
    init(xpcClient: XPCClient, databaseManager: DatabaseManager, powerInterval: Int = 1, wifiInterval: Int = 1) {
        self.xpcClient = xpcClient
        self.databaseManager = databaseManager
        self.powerSamplingIntervalSec = powerInterval
        self.wifiSamplingIntervalSec = wifiInterval
        self.currentPowerInterval = powerInterval
    }

    // MARK: - Lifecycle

    /// Helper が接続済みかどうか
    private(set) var helperAvailable: Bool = false

    /// Collector を開始する
    ///
    /// 1. GET_SERVICE_STATUS で Helper 接続を確認 (タイムアウト付き)
    /// 2. GET_CAPABILITIES で能力を検出
    /// 3. 状態遷移判定
    /// 4. タイマー開始 (Helper 不在時は Wi-Fi タイマーのみ)
    func start() async {
        Self.logger.info("Collector starting")

        isRunning = true
        configureXPCEventHandlers()

        // XPC 接続
        xpcClient.connect()

        // 1. GET_SERVICE_STATUS (Helper 不在の場合はタイムアウトで即座に notReady へ)
        do {
            let status = try await xpcClient.getServiceStatus()
            Self.logger.info("Service status: \(status.serviceState.rawValue), privilege: \(status.privilegeState.rawValue)")

            if status.privilegeState == .denied {
                await handleEvent(.helperUnavailable)
                await startWithoutHelper()
                return
            }
            helperAvailable = true
        } catch {
            Self.logger.warning("GET_SERVICE_STATUS failed (Helper likely not available): \(error.localizedDescription)")
            await handleEvent(.helperUnavailable)
            await startWithoutHelper()
            return
        }

        // 2. GET_CAPABILITIES
        do {
            let caps = try await xpcClient.getCapabilities()
            self.capabilities = caps
            Self.logger.info("Capabilities: \(caps.hardwareFamily.rawValue), profiles: \(caps.profiles.count)")

            let hasPowerProfile = caps.profiles.contains { $0.sourceLevel == "A" || $0.sourceLevel == "B" }
            if hasPowerProfile {
                self.activeProfileId = caps.profiles.first(where: { $0.sourceLevel == "A" })?.profileId
                    ?? caps.profiles.first?.profileId
                await handleEvent(.capabilitiesReady)
            } else {
                await handleEvent(.capabilitiesLimited)
            }
        } catch {
            Self.logger.error("GET_CAPABILITIES failed: \(error.localizedDescription)")
            await handleEvent(.helperUnavailable)
            await startWithoutHelper()
            return
        }

        // 3. 設定読み込み
        await loadSettings()

        // 4. 未実行のロールアップを補完
        await checkPendingRollups()

        // 5. 起動時に全ロールアップを現在の料金設定で再計算する
        await recalculateAllRollups()

        // 6. タイマー開始
        startTimers()

        Self.logger.info("Collector started in state: \(self.state.rawValue)")
    }

    /// Helper 不在時の起動フロー: 設定読み込み、Wi-Fi タイマー、メンテナンスタイマーを開始する
    /// Wi-Fi カウンタは getifaddrs() でローカル読み取りするため root 不要
    private func startWithoutHelper() async {
        Self.logger.info("Starting without Helper - Wi-Fi only mode")

        // 設定読み込み
        await loadSettings()

        // 未実行のロールアップを補完
        await checkPendingRollups()

        // 起動時に全ロールアップを現在の料金設定で再計算する
        await recalculateAllRollups()

        // Wi-Fi タイマー + メンテナンスタイマーを開始（電力は Helper 必要）
        startWifiAndMaintenanceTimers()

        // 初回 Wi-Fi 取得を即座に実行
        await collectWifiSnapshot()

        Self.logger.info("Collector started in state: \(self.state.rawValue) (Wi-Fi only, Helper not available)")
    }

    /// Collector を停止する
    func stop() async {
        Self.logger.info("Collector stopping")
        isRunning = false
        stopTimers()
        stopHelperRecoveryTask()
        xpcClient.onInterruption = nil
        xpcClient.onInvalidation = nil
        xpcClient.disconnect()
    }

    // MARK: - Sampling

    /// 電力サンプルを1件取得して保存する
    func collectPowerSample() async {
        guard state == .normal || state == .degraded else { return }
        guard let profileId = activeProfileId else { return }

        do {
            let response = try await xpcClient.requestPowerSample(
                profileId: profileId,
                timeoutSec: 8,
                collectDebugRaw: debugCaptureEnabled
            )

            let now = Int64(Date().timeIntervalSince1970 * 1000)
            let kwhCalc = PowerKwhCalculator()

            // データ品質チェック
            var status = PowerSample.SampleStatus(rawValue: response.status) ?? .fail
            var outlierFlag = 0

            if let watts = response.avgWatts {
                if watts < 0 {
                    status = .fail // PWR-Q1
                } else if kwhCalc.isOutlier(watts) {
                    outlierFlag = 1 // PWR-Q2
                }
            }

            let sample = PowerSample(
                id: nil,
                capturedAtMs: now,
                avgWatts: response.avgWatts,
                sampleDurationSec: response.sampleDurationSec ?? Double(powerSamplingIntervalSec),
                sourceLevel: PowerSample.SourceLevel(rawValue: response.sourceLevel) ?? .c,
                status: status,
                parserStatus: PowerSample.ParserStatus(rawValue: response.parserStatus) ?? .fail,
                outlierFlag: outlierFlag,
                rawCaptureId: response.rawCaptureId,
                errorCode: response.errorCode
            )

            // DB 保存
            var didSaveSample = false
            do {
                try await flushCaches()
                try databaseManager.insertPowerSample(sample)
                try saveDebugCaptureIfPresent(response: response, capturedAtMs: now)
                didSaveSample = true
            } catch {
                Self.logger.error("Failed to save power sample: \(error.localizedDescription)")
                cachePowerSample(sample)
            }

            latestPowerSample = sample

            // 成功判定
            if status == .success || status == .partial {
                consecutiveFailureCount = 0
                lastSuccessAtMs = now
                lastPowerSuccessAtMs = now
                currentPowerInterval = powerSamplingIntervalSec

                // stale 回復
                if isPowerStale {
                    isPowerStale = false
                }

                if state == .degraded {
                    await handleEvent(.sampleSuccess)
                }

                if didSaveSample {
                    await performTodayRollupIfNeeded(minIntervalSec: 60)
                }
            } else {
                consecutiveFailureCount += 1
                if consecutiveFailureCount >= 3 && state == .normal {
                    await handleEvent(.consecutiveFailures)
                }
                if consecutiveFailureCount >= 3 {
                    // バックオフ: 間隔を2倍、最大10分
                    currentPowerInterval = min(currentPowerInterval * 2, 600)
                }
            }

        } catch {
            Self.logger.error("Power sample collection failed: \(error.localizedDescription)")
            consecutiveFailureCount += 1
            if consecutiveFailureCount >= 3 && state == .normal {
                await handleEvent(.consecutiveFailures)
            }
            if consecutiveFailureCount >= 3 {
                currentPowerInterval = min(currentPowerInterval * 2, 600)
            }
        }

        // Stale 検出 (電力): 採取間隔 × 2
        checkPowerStale()
    }

    /// Wi-Fi スナップショットを取得して差分計算・保存する
    /// Helper 経由またはローカル直接読み取りで Wi-Fi カウンタを取得する
    func collectWifiSnapshot() async {
        let interfaceName: String
        let sentTotal: Int64
        let recvTotal: Int64

        if helperAvailable {
            // Helper 経由
            do {
                let response = try await xpcClient.requestWifiSnapshot()
                guard response.status == "success",
                      let name = response.interfaceName,
                      let sent = response.sentBytesTotal,
                      let recv = response.recvBytesTotal else {
                    Self.logger.warning("Wi-Fi snapshot returned non-success: \(response.status)")
                    return
                }
                interfaceName = name
                sentTotal = sent
                recvTotal = recv
            } catch {
                Self.logger.warning("Wi-Fi via Helper failed, trying local: \(error.localizedDescription)")
                // フォールバック: ローカル直接読み取り
                guard let local = readWifiCountersLocally() else { return }
                interfaceName = local.interfaceName
                sentTotal = local.sentBytesTotal
                recvTotal = local.recvBytesTotal
            }
        } else {
            // Helper なし: ローカル直接読み取り（getifaddrs は root 不要）
            guard let local = readWifiCountersLocally() else { return }
            interfaceName = local.interfaceName
            sentTotal = local.sentBytesTotal
            recvTotal = local.recvBytesTotal
        }

        let now = Int64(Date().timeIntervalSince1970 * 1000)

        // 差分計算
        var sentDelta: Int64 = 0
        var recvDelta: Int64 = 0
        var counterResetFlag = 0

        if let prev = previousWifiSnapshot,
           let prevSent = prev.sentBytesTotal,
           let prevRecv = prev.recvBytesTotal {
            let rawSentDelta = sentTotal - prevSent
            let rawRecvDelta = recvTotal - prevRecv

            if rawSentDelta < 0 || rawRecvDelta < 0 {
                // カウンタリセット検出
                counterResetFlag = 1
                sentDelta = 0
                recvDelta = 0
            } else {
                sentDelta = rawSentDelta
                recvDelta = rawRecvDelta
            }
        }
        // 初回は基準点として delta=0

        let sample = WifiSample(
            id: nil,
            capturedAtMs: now,
            interfaceName: interfaceName,
            sentBytesTotal: sentTotal,
            recvBytesTotal: recvTotal,
            sentBytesDelta: sentDelta,
            recvBytesDelta: recvDelta,
            counterResetFlag: counterResetFlag,
            status: .success,
            errorCode: nil
        )

        // DB 保存 (キャッシュ済みサンプルも先にフラッシュする)
        do {
            try await flushCaches()
            try databaseManager.insertWifiSample(sample)
        } catch {
            Self.logger.error("Failed to save wifi sample: \(error.localizedDescription)")
            cacheWifiSample(sample)
        }

        latestWifiSample = sample
        lastWifiSuccessAtMs = now

        // stale 回復
        if isWifiStale {
            isWifiStale = false
        }

        // Stale 検出 (Wi-Fi): 採取間隔 × 3
        checkWifiStale()

        // previousWifiSnapshot を更新（次回差分計算用）
        let snapshotForNext = WifiSnapshotResponse(
            status: "success",
            interfaceName: interfaceName,
            sentBytesTotal: sentTotal,
            recvBytesTotal: recvTotal,
            errorCode: nil
        )
        previousWifiSnapshot = snapshotForNext
    }

    // MARK: - State

    /// 状態遷移を実行する
    @discardableResult
    func handleEvent(_ event: CollectorEvent) async -> CollectorState? {
        guard let newState = state.transition(on: event) else {
            return nil
        }

        let oldState = state
        state = newState
        Self.logger.info("State transition: \(oldState.rawValue) -> \(newState.rawValue) on event \(String(describing: event))")

        // 監査ログ
        let detail = AuditEventDetail(
            previousValue: .string(oldState.rawValue),
            newValue: .string(newState.rawValue)
        )
        if let detailJson = try? JSONEncoder().encode(detail), let jsonStr = String(data: detailJson, encoding: .utf8) {
            let auditEvent = AuditEvent(
                id: nil,
                occurredAtMs: Int64(Date().timeIntervalSince1970 * 1000),
                eventType: .stateTransition,
                severity: .info,
                component: "CollectorController",
                errorCode: nil,
                detailJson: jsonStr
            )
            try? databaseManager.insertAuditEvent(auditEvent)
        }

        return newState
    }

    /// 最新の電力値を取得する (UI表示用)
    func getLatestPowerSample() -> PowerSample? {
        return latestPowerSample
    }

    /// 最新の Wi-Fi 値を取得する (UI表示用)
    func getLatestWifiSample() -> WifiSample? {
        return latestWifiSample
    }

    // MARK: - Rollup & Maintenance

    /// 日次ロールアップを実行する
    func performRollup(for dateLocal: String) async {
        Self.logger.info("Performing rollup for \(dateLocal)")

        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        guard let date = formatter.date(from: dateLocal) else {
            Self.logger.error("Invalid date format: \(dateLocal)")
            return
        }

        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!.addingTimeInterval(-0.001)

        let startMs = Int64(startOfDay.timeIntervalSince1970 * 1000)
        let endMs = Int64(endOfDay.timeIntervalSince1970 * 1000)

        // 集計対象秒数の決定
        let today = formatter.string(from: Date())
        let targetSeconds: Int
        if dateLocal == today {
            targetSeconds = CoverageRatioCalculator().currentDayElapsedSeconds()
        } else {
            targetSeconds = CoverageRatioCalculator.fullDaySeconds
        }

        do {
            let powerSamples = try databaseManager.fetchPowerSamples(fromMs: startMs, toMs: endMs)
            let wifiSamples = try databaseManager.fetchWifiSamples(fromMs: startMs, toMs: endMs)

            // 料金設定を DB から取得
            let tariffSettings = try loadTariffSettings()

            let rollup = rollupCalculator.calculateRollup(
                dateLocal: dateLocal,
                powerSamples: powerSamples,
                wifiSamples: wifiSamples,
                tariffSettings: tariffSettings,
                targetSeconds: targetSeconds,
                powerSamplingIntervalSec: powerSamplingIntervalSec,
                wifiSamplingIntervalSec: wifiSamplingIntervalSec
            )

            try databaseManager.upsertDailyRollup(rollup)

            // メンテナンスログ
            try databaseManager.insertMaintenanceLog(
                ranAtMs: Int64(Date().timeIntervalSince1970 * 1000),
                jobName: "rollup",
                result: "success",
                deletedRows: 0,
                notes: "date=\(dateLocal)"
            )

            Self.logger.info("Rollup completed for \(dateLocal)")
        } catch {
            Self.logger.error("Rollup failed for \(dateLocal): \(error.localizedDescription)")
        }
    }

    /// パージを実行する
    func performPurge() async {
        Self.logger.info("Performing purge (retention=\(self.retentionDays) days)")

        do {
            let deletedRows = try databaseManager.purge(retentionDays: retentionDays)

            try databaseManager.insertMaintenanceLog(
                ranAtMs: Int64(Date().timeIntervalSince1970 * 1000),
                jobName: "purge",
                result: "success",
                deletedRows: deletedRows,
                notes: nil
            )

            Self.logger.info("Purge completed: \(deletedRows) rows deleted")

            // VACUUM 条件判定
            try databaseManager.vacuumIfNeeded()
        } catch {
            Self.logger.error("Purge failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Settings

    /// 設定を再読み込みする
    func reloadSettings() async {
        await loadSettings()
        // 料金設定変更に伴い、既存ロールアップを再計算する
        await recalculateAllRollups()
        // タイマーを再設定
        stopTimers()
        startTimers()
    }

    /// サンプルが存在する全日付のロールアップを現在の料金設定で計算・更新する
    ///
    /// 料金設定変更時や起動時に呼び出す。既存の rollup だけでなく、
    /// サンプルが存在するがまだ rollup がない日も対象にする。
    func recalculateAllRollups() async {
        Self.logger.info("Recalculating all daily rollups with current tariff settings")

        do {
            let dates = try databaseManager.fetchAllSampleDates()
            guard !dates.isEmpty else {
                Self.logger.info("No sample dates found to calculate rollups")
                return
            }

            let tariffSettings = try loadTariffSettings()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            let todayStr = formatter.string(from: Date())

            for dateLocal in dates {
                guard let date = formatter.date(from: dateLocal) else { continue }
                let calendar = Calendar.current
                let startOfDay = calendar.startOfDay(for: date)
                let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!.addingTimeInterval(-0.001)
                let startMs = Int64(startOfDay.timeIntervalSince1970 * 1000)
                let endMs = Int64(endOfDay.timeIntervalSince1970 * 1000)

                let targetSeconds: Int
                if dateLocal == todayStr {
                    targetSeconds = CoverageRatioCalculator().currentDayElapsedSeconds()
                } else {
                    targetSeconds = CoverageRatioCalculator.fullDaySeconds
                }

                let powerSamples = try databaseManager.fetchPowerSamples(fromMs: startMs, toMs: endMs)
                let wifiSamples = try databaseManager.fetchWifiSamples(fromMs: startMs, toMs: endMs)

                let rollup = rollupCalculator.calculateRollup(
                    dateLocal: dateLocal,
                    powerSamples: powerSamples,
                    wifiSamples: wifiSamples,
                    tariffSettings: tariffSettings,
                    targetSeconds: targetSeconds,
                    powerSamplingIntervalSec: powerSamplingIntervalSec,
                    wifiSamplingIntervalSec: wifiSamplingIntervalSec
                )

                try databaseManager.upsertDailyRollup(rollup)
            }

            Self.logger.info("Recalculated \(dates.count) rollups")
        } catch {
            Self.logger.error("Failed to recalculate rollups: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func saveDebugCaptureIfPresent(response: PowerSampleResponse, capturedAtMs: Int64) throws {
        guard let rawCaptureId = response.rawCaptureId else { return }
        guard response.debugRawStdout != nil || response.debugRawStderr != nil || response.debugExitCode != nil else { return }

        try databaseManager.insertDebugCapture(
            id: rawCaptureId,
            capturedAtMs: capturedAtMs,
            command: "/usr/bin/powermetrics --sample-count 1 --sample-rate 500 -f plist --samplers cpu_power",
            rawStdout: response.debugRawStdout,
            rawStderr: response.debugRawStderr,
            exitCode: response.debugExitCode,
            relatedSampleId: nil
        )
    }

    private func loadSettings() async {
        do {
            if let setting = try databaseManager.fetchSetting(key: AppSetting.Key.powerSamplingIntervalSec.rawValue) {
                if let value = setting.valueNumber { powerSamplingIntervalSec = Int(value) }
            }
            if let setting = try databaseManager.fetchSetting(key: AppSetting.Key.wifiSamplingIntervalSec.rawValue) {
                if let value = setting.valueNumber { wifiSamplingIntervalSec = Int(value) }
            }
            if let setting = try databaseManager.fetchSetting(key: AppSetting.Key.retentionDays.rawValue) {
                if let value = setting.valueNumber { retentionDays = Int(value) }
            }
            if let setting = try databaseManager.fetchSetting(key: AppSetting.Key.debugCaptureEnabled.rawValue) {
                debugCaptureEnabled = setting.valueBool == 1
            }
            currentPowerInterval = powerSamplingIntervalSec
        } catch {
            Self.logger.error("Failed to load settings: \(error.localizedDescription)")
        }
    }

    private func loadTariffSettings() throws -> TariffSettings {
        let model: TariffModel
        if let s = try databaseManager.fetchSetting(key: AppSetting.Key.networkTariffModel.rawValue),
           let text = s.valueText, let m = TariffModel(rawValue: text) {
            model = m
        } else {
            model = .fixed
        }

        let unitPrice = (try databaseManager.fetchSetting(key: AppSetting.Key.electricityUnitPriceYen.rawValue))?.valueNumber ?? 31.0
        let monthlyFee = (try databaseManager.fetchSetting(key: AppSetting.Key.monthlyFeeYen.rawValue))?.valueNumber
        let pricePerGb = (try databaseManager.fetchSetting(key: AppSetting.Key.pricePerGbYen.rawValue))?.valueNumber
        let maxMonthlyFee = (try databaseManager.fetchSetting(key: AppSetting.Key.maxMonthlyFeeYen.rawValue))?.valueNumber
        let resetDay = (try databaseManager.fetchSetting(key: AppSetting.Key.monthlyResetDay.rawValue))?.valueNumber.flatMap { Int($0) } ?? 1

        return TariffSettings(
            model: model,
            electricityUnitPriceYen: unitPrice,
            monthlyFeeYen: monthlyFee,
            pricePerGbYen: pricePerGb,
            maxMonthlyFeeYen: maxMonthlyFee,
            monthlyResetDay: resetDay
        )
    }

    private func startTimers() {
        startPowerTimer()
        startWifiTimer(collectImmediately: true)
        startAttributedUsageTimer()
        startMaintenanceTimer()
        startTodayRollupTask()
    }

    private func startPowerTimer() {
        guard powerTask == nil else { return }

        powerTask = Task { [weak self] in
            guard let self = self else { return }
            await self.collectPowerSample()
            while !Task.isCancelled {
                let interval = await self.currentPowerInterval
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                await self.collectPowerSample()
            }
        }
    }

    private func stopPowerTimer() {
        powerTask?.cancel()
        powerTask = nil
    }

    private func startWifiTimer(collectImmediately: Bool) {
        guard wifiTask == nil else { return }

        wifiTask = Task { [weak self] in
            guard let self = self else { return }
            if collectImmediately {
                await self.collectWifiSnapshot()
            }
            while !Task.isCancelled {
                let interval = await self.wifiSamplingIntervalSec
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                await self.collectWifiSnapshot()
            }
        }
    }

    private func startMaintenanceTimer() {
        guard maintenanceTask == nil else { return }

        maintenanceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600))
                guard !Task.isCancelled, let self = self else { return }
                await self.checkMaintenanceSchedule()
            }
        }
    }

    /// アプリ・接続先別の通信量を低頻度で採取する。`nettop` はスナップショットの
    /// 累積カウンタを返すため、前回値との差分だけを保存する。
    private func startAttributedUsageTimer() {
        guard attributedUsageTask == nil else { return }
        attributedUsageTask = Task { [weak self] in
            guard let self else { return }
            await self.collectAttributedUsage()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                await self.collectAttributedUsage()
            }
        }
    }

    private func collectAttributedUsage() {
        let flows = (try? ProcessNetworkUsageReader().readFlows()) ?? []
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let totalDelta = flows.reduce(Int64(0)) { partial, flow in
            guard let previous = previousAttributedFlows[flow.key] else { return partial }
            return partial + max(0, flow.receivedBytesTotal - previous.receivedBytesTotal)
                + max(0, flow.sentBytesTotal - previous.sentBytesTotal)
        }
        let currentWatts = latestPowerSample?.avgWatts

        for flow in flows {
            guard let previous = previousAttributedFlows[flow.key] else { continue }
            let received = max(0, flow.receivedBytesTotal - previous.receivedBytesTotal)
            let sent = max(0, flow.sentBytesTotal - previous.sentBytesTotal)
            guard received + sent > 0 else { continue }
            let estimatedWatts = currentWatts.map { $0 * Double(received + sent) / Double(max(totalDelta, 1)) }
            try? databaseManager.insertAttributedUsage(AttributedUsage(
                id: nil, capturedAtMs: nowMs, applicationName: flow.applicationName,
                bundleIdentifier: nil, destinationHost: flow.destinationHost,
                sentBytes: sent, receivedBytes: received, estimatedWatts: estimatedWatts
            ))
        }
        // `nettop` can report multiple identical flow labels. Never use
        // Dictionary(uniqueKeysWithValues:) here: it traps on a duplicate and
        // would terminate the app during its first collection cycle.
        var nextFlows: [String: ProcessNetworkUsageReader.Flow] = [:]
        for flow in flows {
            nextFlows[flow.key] = flow
        }
        previousAttributedFlows = nextFlows
    }

    /// 当日分のロールアップを60秒ごとに更新するタスクを開始する
    private func startTodayRollupTask() {
        guard todayRollupTask == nil else { return }

        todayRollupTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled, let self = self else { return }
                await self.performTodayRollup()
            }
        }
    }

    private func stopTimers() {
        powerTask?.cancel()
        powerTask = nil
        wifiTask?.cancel()
        wifiTask = nil
        attributedUsageTask?.cancel()
        attributedUsageTask = nil
        maintenanceTask?.cancel()
        maintenanceTask = nil
        todayRollupTask?.cancel()
        todayRollupTask = nil
    }

    /// Wi-Fi タスク + メンテナンスタスクを開始する (Helper 不在時用)
    private func startWifiAndMaintenanceTimers() {
        startWifiTimer(collectImmediately: false)
        startAttributedUsageTimer()
        startMaintenanceTimer()
        startTodayRollupTask()
        startHelperRecoveryTask()
    }

    private func performTodayRollup() async {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        await performRollup(for: formatter.string(from: Date()))
        lastTodayRollupAtMs = Int64(Date().timeIntervalSince1970 * 1000)
    }

    private func performTodayRollupIfNeeded(minIntervalSec: Int) async {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        if let lastTodayRollupAtMs,
           nowMs - lastTodayRollupAtMs < Int64(minIntervalSec) * 1000 {
            return
        }
        await performTodayRollup()
    }

    private func configureXPCEventHandlers() {
        xpcClient.onInterruption = { [weak self] in
            Task { await self?.handleHelperConnectionLost() }
        }
        xpcClient.onInvalidation = { [weak self] in
            Task { await self?.handleHelperConnectionLost() }
        }
    }

    private func handleHelperConnectionLost() async {
        guard isRunning else { return }
        helperAvailable = false
        activeProfileId = nil
        stopPowerTimer()
        await handleEvent(.helperUnavailable)
        startHelperRecoveryTask()
    }

    private func startHelperRecoveryTask() {
        guard isRunning else { return }
        guard helperRecoveryTask == nil else { return }

        helperRecoveryTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                if await self.tryRecoverHelperConnection() {
                    return
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func stopHelperRecoveryTask() {
        helperRecoveryTask?.cancel()
        helperRecoveryTask = nil
    }

    private func tryRecoverHelperConnection() async -> Bool {
        guard isRunning else { return true }
        xpcClient.connect()

        do {
            let status = try await xpcClient.getServiceStatus()
            guard status.privilegeState != .denied else {
                helperAvailable = false
                return false
            }

            let caps = try await xpcClient.getCapabilities()
            let hasPowerProfile = caps.profiles.contains { $0.sourceLevel == "A" || $0.sourceLevel == "B" }
            guard hasPowerProfile else {
                capabilities = caps
                helperAvailable = true
                await handleEvent(.privilegeGranted)
                await handleEvent(.capabilitiesLimited)
                return false
            }

            capabilities = caps
            activeProfileId = caps.profiles.first(where: { $0.sourceLevel == "A" })?.profileId
                ?? caps.profiles.first(where: { $0.sourceLevel == "B" })?.profileId
            helperAvailable = true
            consecutiveFailureCount = 0
            currentPowerInterval = powerSamplingIntervalSec

            await handleEvent(.privilegeGranted)
            await handleEvent(.capabilitiesReady)
            stopHelperRecoveryTask()
            startPowerTimer()
            Self.logger.info("Helper recovered; power sampling restarted")
            return true
        } catch {
            helperAvailable = false
            Self.logger.warning("Helper recovery check failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Stale Detection (M-007)

    /// 電力の stale を検出する (閾値: 採取間隔 × 2)
    private func checkPowerStale() {
        guard let lastMs = lastPowerSuccessAtMs else { return }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let thresholdMs = Int64(powerSamplingIntervalSec * 2) * 1000
        if nowMs - lastMs > thresholdMs {
            if !isPowerStale {
                isPowerStale = true
                Self.logger.warning("Power data is stale: elapsed \((nowMs - lastMs) / 1000)s > threshold \(thresholdMs / 1000)s")
            }
        } else {
            isPowerStale = false
        }
    }

    /// Wi-Fi の stale を検出する (閾値: 採取間隔 × 3)
    private func checkWifiStale() {
        guard let lastMs = lastWifiSuccessAtMs else { return }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let thresholdMs = Int64(wifiSamplingIntervalSec * 3) * 1000
        if nowMs - lastMs > thresholdMs {
            if !isWifiStale {
                isWifiStale = true
                Self.logger.warning("Wi-Fi data is stale: elapsed \((nowMs - lastMs) / 1000)s > threshold \(thresholdMs / 1000)s")
            }
        } else {
            isWifiStale = false
        }
    }

    // MARK: - Wi-Fi Baseline Reset (Sleep/Wake)

    /// Wi-Fi カウンタの差分計算基準をリセットする
    ///
    /// wake 復帰時に呼び出す。スリープ中のカウンタ変動で巨大な差分が
    /// 計上されることを防ぐ (counter_reset_flag=1 として扱う)。
    func resetWifiBaseline() {
        previousWifiSnapshot = nil
        Self.logger.info("Wi-Fi baseline reset (counter_reset_flag will be set on next sample)")
    }

    // MARK: - Wi-Fi Counter Reading

    /// CWWiFiClient を使って Wi-Fi インターフェース名を動的に特定する
    ///
    /// 第8.1節: en0 固定にせず CWWiFiClient.shared().interface()?.interfaceName で動的に特定する。
    /// CWWiFiClient が利用不可の場合は "en0" にフォールバック。
    private nonisolated func resolveWifiInterfaceName() -> String {
        if let wifiInterface = CWWiFiClient.shared().interface(),
           let name = wifiInterface.interfaceName {
            return name
        }
        return "en0"
    }

    /// Wi-Fi カウンタをローカルで直接読み取る (getifaddrs は root 不要)
    ///
    /// CWWiFiClient で特定した Wi-Fi インターフェース名に一致するカウンタのみ返す。
    private nonisolated func readWifiCountersLocally() -> (interfaceName: String, sentBytesTotal: Int64, recvBytesTotal: Int64)? {
        let targetInterface = resolveWifiInterfaceName()

        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0 else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        // CWWiFiClient で特定したインターフェース名に一致するものを探す
        var ptr = ifaddrPtr
        while let ifaddr = ptr {
            let name = String(cString: ifaddr.pointee.ifa_name)
            if name == targetInterface,
               ifaddr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK),
               let data = ifaddr.pointee.ifa_data {
                let ifData = data.assumingMemoryBound(to: if_data.self).pointee
                return (name, Int64(ifData.ifi_obytes), Int64(ifData.ifi_ibytes))
            }
            ptr = ifaddr.pointee.ifa_next
        }

        // フォールバック: targetInterface が見つからない場合、en で始まるインターフェースを探す
        ptr = ifaddrPtr
        while let ifaddr = ptr {
            let name = String(cString: ifaddr.pointee.ifa_name)
            if name.hasPrefix("en"),
               ifaddr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK),
               let data = ifaddr.pointee.ifa_data {
                let ifData = data.assumingMemoryBound(to: if_data.self).pointee
                Self.logger.warning("Wi-Fi interface \(targetInterface) not found in ifaddrs, falling back to \(name)")
                return (name, Int64(ifData.ifi_obytes), Int64(ifData.ifi_ibytes))
            }
            ptr = ifaddr.pointee.ifa_next
        }
        return nil
    }

    private func checkMaintenanceSchedule() async {
        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        // 00:10 にロールアップ (前日分)
        if hour == 0 && minute >= 10 && minute < 70 {
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
            let dateStr = formatter.string(from: yesterday)
            await performRollup(for: dateStr)
        }

        // 03:10 にパージ
        if hour == 3 && minute >= 10 && minute < 70 {
            await performPurge()
        }
    }

    private func checkPendingRollups() async {
        // 前回ロールアップの実行日を確認
        guard let lastRollup = try? databaseManager.fetchLatestMaintenanceLog(jobName: "rollup") else {
            // 初回 — 当日のロールアップは不要
            return
        }

        let lastRollupDate = Date(timeIntervalSince1970: Double(lastRollup.ranAtMs) / 1000.0)
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        var checkDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: lastRollupDate))!
        let today = calendar.startOfDay(for: Date())

        while checkDate < today {
            let dateStr = formatter.string(from: checkDate)
            await performRollup(for: dateStr)
            checkDate = calendar.date(byAdding: .day, value: 1, to: checkDate)!
        }
    }

    /// メモリキャッシュに電力サンプルを追加する (DB書込み失敗時の退避)
    private func cachePowerSample(_ sample: PowerSample) {
        if powerSampleCache.count >= Self.cacheLimit {
            powerSampleCache.removeFirst()
        }
        powerSampleCache.append(sample)
    }

    /// メモリキャッシュに Wi-Fi サンプルを追加する (DB書込み失敗時の退避)
    private func cacheWifiSample(_ sample: WifiSample) {
        if wifiSampleCache.count >= Self.cacheLimit {
            wifiSampleCache.removeFirst()
        }
        wifiSampleCache.append(sample)
    }

    /// キャッシュされたサンプルを DB に書き戻す
    private func flushCaches() async throws {
        // 電力キャッシュ
        var failedPower: [PowerSample] = []
        for sample in powerSampleCache {
            do {
                try databaseManager.insertPowerSample(sample)
            } catch {
                failedPower.append(sample)
            }
        }
        powerSampleCache = failedPower

        // Wi-Fi キャッシュ
        var failedWifi: [WifiSample] = []
        for sample in wifiSampleCache {
            do {
                try databaseManager.insertWifiSample(sample)
            } catch {
                failedWifi.append(sample)
            }
        }
        wifiSampleCache = failedWifi
    }
}
