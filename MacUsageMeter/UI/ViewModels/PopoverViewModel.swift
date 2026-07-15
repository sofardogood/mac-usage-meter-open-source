import Foundation
import Combine
import SwiftUI

/// ポップオーバー画面の ViewModel (G-002)
///
/// 1秒ごとの表示更新、最新値のフォーマット、状態管理を担当する。
@MainActor
final class PopoverViewModel: ObservableObject {

    // MARK: - Published Properties

    /// 現在電力 (W)
    @Published var currentWatts: Double?

    /// 直近1時間の平均電力 (W)
    @Published var recentAverageWatts: Double?

    /// 今日の Wi-Fi 使用量 (バイト)
    @Published var todayWifiBytes: Int64 = 0

    /// 今日の概算電気代 (円、税別)
    @Published var todayPowerCostYen: Double?

    /// 今日の概算通信費 (円、税別)
    @Published var todayNetworkCostYen: Double?

    /// 月次概算電気代 (円、税別) - monthly_reset_day 基準
    @Published var monthlyPowerCostYen: Double?

    /// 月次概算通信費 (円、税別) - monthly_reset_day 基準
    @Published var monthlyNetworkCostYen: Double?

    /// 月次合計電力量 (kWh)
    @Published var monthlyPowerKwh: Double?

    /// 月次合計 Wi-Fi 使用量 (GB)
    @Published var monthlyWifiGb: Double?

    /// 月次合計料金 (円、税別)
    var monthlyTotalCostYen: Double? {
        let power = monthlyPowerCostYen ?? 0
        let network = monthlyNetworkCostYen ?? 0
        if monthlyPowerCostYen == nil && monthlyNetworkCostYen == nil { return nil }
        return power + network
    }

    /// 今日の電力量 (kWh)
    @Published var todayPowerKwh: Double?

    /// 月次期間ラベル (例: "3/15〜4/14")
    @Published var monthlyPeriodLabel: String = ""

    /// 最終更新時刻
    @Published var lastUpdatedAt: Date?

    /// 状態メッセージ
    @Published var statusMessage: String = "正常"

    /// 現在の状態コード
    @Published var activeStateCodes: [StateCode] = []

    /// ミニグラフ用の電力サンプル (直近1時間)
    @Published var recentPowerSamples: [PowerSample] = []

    /// Collector 状態
    @Published var collectorState: CollectorState = .starting

    // MARK: - Dependencies

    private let collectorController: CollectorController
    private let databaseManager: DatabaseManager
    private var timerCancellable: AnyCancellable?

    /// 通知重複抑止 (第13.2節)
    private let notificationThrottler = NotificationThrottler()

    // MARK: - Initialization

    init(collectorController: CollectorController, databaseManager: DatabaseManager) {
        self.collectorController = collectorController
        self.databaseManager = databaseManager
    }

    // MARK: - Lifecycle

    /// 表示更新タイマーを開始する (1秒間隔)
    func startUpdating() {
        refresh()
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
    }

    /// 表示更新タイマーを停止する
    func stopUpdating() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    /// 最新データを取得して表示を更新する
    func refresh() {
        Task {
            // 最新電力サンプル
            let latestPower = await collectorController.getLatestPowerSample()
            if let sample = latestPower, sample.avgWatts != nil {
                currentWatts = sample.avgWatts
            }

            // DB アクセスをメインスレッド外で実行する (集計クエリで高速化)
            let dbResult = await Task.detached { [databaseManager] in
                let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
                let oneHourAgoMs = nowMs - 3_600_000
                let powerSamples = try? databaseManager.fetchPowerSamples(fromMs: oneHourAgoMs, toMs: nowMs)

                let calendar = Calendar.current
                let startOfDay = calendar.startOfDay(for: Date())
                let startOfDayMs = Int64(startOfDay.timeIntervalSince1970 * 1000)

                // 今日の集計値 (SQL SUM で高速取得)
                let todayWifiBytes = (try? databaseManager.sumWifiBytes(fromMs: startOfDayMs, toMs: nowMs)) ?? 0
                let todayPowerKwh = (try? databaseManager.sumPowerKwh(fromMs: startOfDayMs, toMs: nowMs)) ?? 0.0

                // 料金設定を取得する
                let tariffModel: TariffModel
                if let s = try? databaseManager.fetchSetting(key: AppSetting.Key.networkTariffModel.rawValue),
                   let text = s.valueText, let m = TariffModel(rawValue: text) {
                    tariffModel = m
                } else {
                    tariffModel = .fixed
                }
                let electricityUnitPrice = (try? databaseManager.fetchSetting(key: AppSetting.Key.electricityUnitPriceYen.rawValue))?.valueNumber ?? 31.0
                let monthlyFee = (try? databaseManager.fetchSetting(key: AppSetting.Key.monthlyFeeYen.rawValue))?.valueNumber
                let pricePerGb = (try? databaseManager.fetchSetting(key: AppSetting.Key.pricePerGbYen.rawValue))?.valueNumber
                let maxMonthlyFee = (try? databaseManager.fetchSetting(key: AppSetting.Key.maxMonthlyFeeYen.rawValue))?.valueNumber

                // 月次リセット日を取得し、月次期間を計算する
                let resetDay = (try? databaseManager.fetchSetting(key: AppSetting.Key.monthlyResetDay.rawValue))?.valueNumber.flatMap { Int($0) } ?? 1
                let period = MonthlyPeriodCalculator.currentPeriod(resetDay: resetDay)
                let monthlyPowerCost = try? databaseManager.fetchMonthlyPowerCost(fromDate: period.startDate, toDate: period.endDate)
                let monthlyWifiGb = try? databaseManager.fetchMonthlyWifiGb(fromDate: period.startDate, toDate: period.endDate)
                let monthlyNetworkCostSum = try? databaseManager.fetchMonthlyNetworkCost(fromDate: period.startDate, toDate: period.endDate)
                let monthlyPowerKwh = try? databaseManager.fetchMonthlyPowerKwh(fromDate: period.startDate, toDate: period.endDate)

                // 今日の rollup (月次リアルタイム計算用)
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                let todayStr = dateFormatter.string(from: Date())
                let todayRollup = (try? databaseManager.fetchDailyRollups(fromDate: todayStr, toDate: todayStr))?.first

                let tariffSettings = TariffSettings(
                    model: tariffModel,
                    electricityUnitPriceYen: electricityUnitPrice,
                    monthlyFeeYen: monthlyFee,
                    pricePerGbYen: pricePerGb,
                    maxMonthlyFeeYen: maxMonthlyFee,
                    monthlyResetDay: resetDay
                )

                return (powerSamples, todayWifiBytes, todayPowerKwh, monthlyPowerCost, monthlyWifiGb, monthlyNetworkCostSum, period, tariffSettings, monthlyPowerKwh, todayRollup)
            }.value

            let tariffSettings = dbResult.7
            let tariffCalculator = TariffCalculator()

            // 直近1時間の電力サンプル (グラフ用 - 行取得が必要)
            if let samples = dbResult.0 {
                recentPowerSamples = samples
                let validSamples = samples.filter { $0.avgWatts != nil && $0.status != .fail }
                if !validSamples.isEmpty {
                    let sum = validSamples.compactMap(\.avgWatts).reduce(0, +)
                    recentAverageWatts = sum / Double(validSamples.count)
                }
            }

            // 今日の Wi-Fi 使用量 (SQL集計で即取得)
            let todayBytes = dbResult.1
            todayWifiBytes = todayBytes
            let todayWifiGb = Double(todayBytes) / 1_000_000_000.0

            // 今日の電力量 (SQL集計で即取得)
            let todayKwh = dbResult.2
            todayPowerKwh = todayKwh
            todayPowerCostYen = tariffCalculator.calculatePowerCost(
                powerKwh: todayKwh,
                unitPriceYen: tariffSettings.electricityUnitPriceYen
            )

            // 今日の通信費
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let todayStr = dateFormatter.string(from: Date())
            let daysInMonth = RollupCalculator.daysInMonth(for: todayStr)
            todayNetworkCostYen = tariffCalculator.calculateDailyNetworkCost(
                wifiGb: todayWifiGb,
                settings: tariffSettings,
                daysInMonth: daysInMonth
            )

            // 月次概算: rollup(過去日分) + 今日のリアルタイム値
            let rollupMonthlyPowerKwh = dbResult.8 ?? 0.0
            let rollupMonthlyWifiGb = dbResult.4 ?? 0.0
            let rollupMonthlyNetworkCostSum = dbResult.5 ?? 0.0

            // 今日のrollup値を差し引いてリアルタイム値で置き換える
            let tr = dbResult.9
            let todayRollupKwh = tr?.powerKwh ?? 0
            let todayRollupWifiGb = tr?.wifiGb ?? 0
            let todayRollupNetworkCost = tr?.networkCostYen ?? 0

            let realtimeMonthlyKwh = (rollupMonthlyPowerKwh - todayRollupKwh) + todayKwh
            let realtimeMonthlyWifiGb = (rollupMonthlyWifiGb - todayRollupWifiGb) + todayWifiGb

            monthlyPowerKwh = realtimeMonthlyKwh
            monthlyWifiGb = realtimeMonthlyWifiGb
            monthlyPowerCostYen = tariffCalculator.calculatePowerCost(
                powerKwh: realtimeMonthlyKwh,
                unitPriceYen: tariffSettings.electricityUnitPriceYen
            )
            monthlyNetworkCostYen = tariffCalculator.calculateMonthlyNetworkCost(
                totalWifiGb: realtimeMonthlyWifiGb,
                totalDailyNetworkCost: (rollupMonthlyNetworkCostSum - todayRollupNetworkCost) + (todayNetworkCostYen ?? 0),
                settings: tariffSettings
            )

            let period = dbResult.6
            monthlyPeriodLabel = Self.formatPeriodLabel(period)

            // Collector 状態
            let state = await collectorController.state
            collectorState = state
            updateStatusMessage(state: state)

            // Stale 検出 (M-007) を activeStateCodes に反映
            let powerStale = await collectorController.isPowerStale
            let wifiStale = await collectorController.isWifiStale
            await updateActiveStateCodes(state: state, isPowerStale: powerStale, isWifiStale: wifiStale)

            // 最終更新時刻を毎回更新（UI更新トリガーも兼ねる）
            lastUpdatedAt = Date()

            // SwiftUI に変更を明示通知
            objectWillChange.send()
        }
    }

    /// 再試行を実行する
    func retry() {
        Task {
            await collectorController.collectPowerSample()
            await collectorController.collectWifiSnapshot()
            refresh()
        }
    }

    // MARK: - Formatting

    /// Wi-Fi 使用量を適応単位で表示する
    var todayWifiUsageText: String {
        Self.formatBytes(todayWifiBytes)
    }

    /// バイト数を適応単位の文字列に変換する
    nonisolated static func formatBytes(_ bytes: Int64) -> String {
        let absBytes = Double(abs(bytes))
        if absBytes < 1_000 {
            return "\(bytes) B"
        } else if absBytes < 1_000_000 {
            return String(format: "%.1f KB", absBytes / 1_000)
        } else if absBytes < 1_000_000_000 {
            return String(format: "%.1f MB", absBytes / 1_000_000)
        } else {
            return String(format: "%.2f GB", absBytes / 1_000_000_000)
        }
    }

    /// 最終更新時刻をフォーマットする
    var lastUpdatedText: String? {
        guard let date = lastUpdatedAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    /// 概算電気代を表示用にフォーマットする
    func formatCostYen(_ value: Double?) -> String {
        guard let value = value else { return "Not calculated" }
        if value < 1 {
            return String(format: "%.4f 円", value)
        } else if value < 100 {
            return String(format: "%.3f 円", value)
        }
        return String(format: "%.2f 円", value)
    }

    /// 月次期間ラベルをフォーマットする (例: "3/15〜4/14")
    nonisolated static func formatPeriodLabel(_ period: MonthlyPeriodCalculator.MonthlyPeriod) -> String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.locale = Locale(identifier: "en_US_POSIX")
        guard let start = parser.date(from: period.startDate),
              let end = parser.date(from: period.endDate) else {
            return "\(period.startDate)〜\(period.endDate)"
        }
        let display = DateFormatter()
        display.dateFormat = "M/d"
        return "\(display.string(from: start))〜\(display.string(from: end))"
    }

    /// 再試行ボタンを表示すべきか
    var shouldShowRetryButton: Bool {
        activeStateCodes.contains(where: \.isRetryable)
    }

    /// 主要な状態コード
    var primaryStateCode: StateCode? {
        activeStateCodes.sorted(by: { $0.priority < $1.priority }).first
    }

    // MARK: - Private

    /// 状態コードを更新し、通知スロットリングを適用する (第6.1節 / 第13.2節)
    ///
    /// Collector の状態と stale フラグから activeStateCodes を構築する。
    /// 新たに追加される状態コードは NotificationThrottler で 30 分以内の重複通知を抑止する。
    private func updateActiveStateCodes(state: CollectorState, isPowerStale: Bool, isWifiStale: Bool) async {
        var codes: [StateCode] = []

        // 状態ベースのコード
        switch state {
        case .starting:
            codes.append(.initialDataPending)
        case .notReady:
            codes.append(.helperNotRegistered)
        case .degraded:
            codes.append(.powerDataFailure)
        case .limitedReady:
            codes.append(.powerMetricsUnsupported)
        case .normal:
            break
        }

        // Stale 検出 (M-007)
        if isPowerStale || isWifiStale {
            codes.append(.staleContinued)
        }

        // 通知スロットリング (第13.2節): 新規追加のコードのみ通知対象
        let previousCodes = Set(activeStateCodes)
        for code in codes {
            if !previousCodes.contains(code) {
                let shouldNotify = await notificationThrottler.shouldNotify(for: code)
                if shouldNotify {
                    await notificationThrottler.recordNotification(for: code)
                    // ここで実際のユーザー通知を発行できる (将来拡張ポイント)
                }
            }
        }

        // 回復したコードのスロットルをリセット
        let currentCodes = Set(codes)
        for code in previousCodes {
            if !currentCodes.contains(code) {
                await notificationThrottler.resetThrottle(for: code)
            }
        }

        activeStateCodes = codes
    }

    private func updateStatusMessage(state: CollectorState) {
        switch state {
        case .normal:
            statusMessage = "Normal"
        case .starting:
            statusMessage = "Starting..."
        case .degraded:
            statusMessage = "Some data is unavailable"
        case .limitedReady:
            statusMessage = "Measuring Wi-Fi only (power is unavailable)"
        case .notReady:
            statusMessage = "Measurement is not ready"
        }
    }
}
