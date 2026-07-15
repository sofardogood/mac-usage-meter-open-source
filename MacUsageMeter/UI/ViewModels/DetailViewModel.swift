import Foundation
import Combine
import SwiftUI
import AppKit
import UniformTypeIdentifiers

func resolveSavePanelWindow(
    presentingWindow: NSWindow?,
    keyWindow: NSWindow?,
    mainWindow: NSWindow?
) -> NSWindow? {
    presentingWindow ?? keyWindow ?? mainWindow
}

/// 詳細画面の ViewModel (G-003)
///
/// 期間別の履歴データ取得、グラフ用データ変換、CSV エクスポートを担当する。
@MainActor
final class DetailViewModel: ObservableObject {

    // MARK: - Published Properties

    /// 電力サンプル (raw)
    @Published var powerSamples: [PowerSample] = []

    /// Wi-Fi サンプル (raw)
    @Published var wifiSamples: [WifiSample] = []

    /// 日次ロールアップ
    @Published var dailyRollups: [DailyRollup] = []

    /// データ読み込み中
    @Published var isLoading: Bool = false

    /// 電力の平均値 (表示用)
    @Published var averagePowerWatts: Double?

    /// 電力の最大値 (表示用)
    @Published var maxPowerWatts: Double?

    /// Wi-Fi 合計使用量 (表示用文字列)
    @Published var totalWifiUsageText: String = "0 B"

    /// Network Extension が観測した利用先別の通信量集計。
    @Published var usageDestinationSummaries: [UsageDestinationSummary] = []

    /// 利用先別の合計通信量（表示用）。
    @Published var attributedUsageTotalBytes: Int64 = 0

    /// CSV エクスポート: 種別
    @Published var exportType: CSVExporter.ExportType = .rawPower

    /// CSV エクスポート: 開始日
    @Published var exportDateFrom: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()

    /// CSV エクスポート: 終了日
    @Published var exportDateTo: Date = Date()

    /// CSV エクスポート: 処理中
    @Published var isExporting: Bool = false

    /// CSV エクスポート: 結果メッセージ
    @Published var exportResultMessage: String?

    // MARK: - Dependencies

    private let databaseManager: DatabaseManager
    private let presentingWindowProvider: () -> NSWindow?

    // MARK: - Initialization

    init(
        databaseManager: DatabaseManager,
        presentingWindowProvider: @escaping () -> NSWindow? = { nil }
    ) {
        self.databaseManager = databaseManager
        self.presentingWindowProvider = presentingWindowProvider
    }

    // MARK: - Data Loading

    /// 指定期間のデータを読み込む
    func loadData(for period: DetailView.Period) {
        isLoading = true
        let calendar = Calendar.current
        let now = Date()

        switch period {
        case .oneHour, .twentyFourHours:
            loadRawData(period: period, calendar: calendar, now: now)
        case .sevenDays, .thirtyDays, .ninetyDays:
            loadRollupData(period: period, calendar: calendar, now: now)
        }
    }

    /// 指定期間のサイト・アプリ別使用量を読み込む。
    func loadUsageBreakdown(for period: DetailView.Period) {
        let now = Date()
        let calendar = Calendar.current
        let hoursBack: Int
        switch period {
        case .oneHour: hoursBack = 1
        case .twentyFourHours: hoursBack = 24
        case .sevenDays: hoursBack = 24 * 7
        case .thirtyDays: hoursBack = 24 * 30
        case .ninetyDays: hoursBack = 24 * 90
        }
        let from = calendar.date(byAdding: .hour, value: -hoursBack, to: now) ?? now

        do {
            let values = try databaseManager.fetchUsageDestinationSummaries(
                fromMs: Int64(from.timeIntervalSince1970 * 1000),
                toMs: Int64(now.timeIntervalSince1970 * 1000)
            )
            usageDestinationSummaries = values
            attributedUsageTotalBytes = values.reduce(0) { $0 + $1.totalBytes }
        } catch {
            usageDestinationSummaries = []
            attributedUsageTotalBytes = 0
        }
    }

    private func loadRawData(period: DetailView.Period, calendar: Calendar, now: Date) {
        let hoursBack: Int = period == .oneHour ? 1 : 24
        let fromDate = calendar.date(byAdding: .hour, value: -hoursBack, to: now) ?? now
        let fromMs = Int64(fromDate.timeIntervalSince1970 * 1000)
        let toMs = Int64(now.timeIntervalSince1970 * 1000)

        do {
            powerSamples = try databaseManager.fetchPowerSamples(fromMs: fromMs, toMs: toMs)
            wifiSamples = try databaseManager.fetchWifiSamples(fromMs: fromMs, toMs: toMs)
            dailyRollups = []

            // 統計計算
            let validPower = powerSamples.compactMap(\.avgWatts).filter { $0 >= 0 }
            averagePowerWatts = validPower.isEmpty ? nil : validPower.reduce(0, +) / Double(validPower.count)
            maxPowerWatts = validPower.max()

            let totalWifiBytes = wifiSamples.reduce(Int64(0)) { $0 + $1.sentBytesDelta + $1.recvBytesDelta }
            totalWifiUsageText = PopoverViewModel.formatBytes(totalWifiBytes)
        } catch {
            powerSamples = []
            wifiSamples = []
        }
        isLoading = false
    }

    private func loadRollupData(period: DetailView.Period, calendar: Calendar, now: Date) {
        let daysBack: Int
        switch period {
        case .sevenDays: daysBack = 7
        case .thirtyDays: daysBack = 30
        case .ninetyDays: daysBack = 90
        default: daysBack = 7
        }

        let fromDate = calendar.date(byAdding: .day, value: -daysBack, to: now) ?? now
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let fromStr = dateFormatter.string(from: fromDate)
        let toStr = dateFormatter.string(from: now)

        do {
            dailyRollups = try databaseManager.fetchDailyRollups(fromDate: fromStr, toDate: toStr)
            powerSamples = []
            wifiSamples = []

            // 統計計算
            let validPower = dailyRollups.compactMap(\.powerKwh).filter { $0 >= 0 }
            if !validPower.isEmpty {
                // 日次の平均消費電力（kWh を日数で平均）
                averagePowerWatts = validPower.reduce(0, +) / Double(validPower.count) * 1000 / 24
            } else {
                averagePowerWatts = nil
            }
            maxPowerWatts = dailyRollups.compactMap(\.powerKwh).max().map { $0 * 1000 / 24 }

            let totalWifiGb = dailyRollups.compactMap(\.wifiGb).reduce(0, +)
            totalWifiUsageText = String(format: "%.2f GB", totalWifiGb)
        } catch {
            dailyRollups = []
        }
        isLoading = false
    }

    // MARK: - CSV Export

    /// CSV エクスポートを実行する
    func exportCSV() {
        Self.requestStatusItemRefresh()

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(exportType.rawValue)_export.csv"
        let parentWindow = exportParentWindow()

        let handleResponse: (NSApplication.ModalResponse) -> Void = { [weak self, weak parentWindow, panel] response in
            Self.requestStatusItemRefresh()
            parentWindow?.makeKeyAndOrderFront(nil)
            guard let self, response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.isExporting = true
                self.exportResultMessage = nil
                await self.performExport(to: url)
                Self.requestStatusItemRefresh()
            }
        }

        if let parentWindow {
            NSApplication.shared.activate(ignoringOtherApps: true)
            parentWindow.makeKeyAndOrderFront(nil)
            panel.beginSheetModal(for: parentWindow, completionHandler: handleResponse)
        } else {
            NSApplication.shared.activate(ignoringOtherApps: true)
            panel.begin(completionHandler: handleResponse)
        }

        DispatchQueue.main.async {
            Self.requestStatusItemRefresh()
        }
    }

    private func performExport(to url: URL) async {
        let fromMs = Int64(exportDateFrom.timeIntervalSince1970 * 1000)
        let toMs = Int64(exportDateTo.timeIntervalSince1970 * 1000)
        let currentExportType = exportType
        let exportFromDate = exportDateFrom
        let exportToDate = exportDateTo

        let result: Result<Void, Error> = await Task.detached { [databaseManager] in
            let exporter = CSVExporter()
            do {
                switch currentExportType {
                case .rawPower:
                    let samples = try databaseManager.fetchPowerSamples(fromMs: fromMs, toMs: toMs)
                    try exporter.exportRawPower(samples: samples, to: url)
                case .rawWifi:
                    let samples = try databaseManager.fetchWifiSamples(fromMs: fromMs, toMs: toMs)
                    try exporter.exportRawWifi(samples: samples, to: url)
                case .dailyRollup:
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd"
                    let fromStr = dateFormatter.string(from: exportFromDate)
                    let toStr = dateFormatter.string(from: exportToDate)
                    let rollups = try databaseManager.fetchDailyRollups(fromDate: fromStr, toDate: toStr)
                    try exporter.exportDailyRollup(rollups: rollups, to: url)
                }
                return .success(())
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success:
            exportResultMessage = "エクスポートが完了しました"
        case .failure(let error):
            exportResultMessage = "エクスポートに失敗しました: \(error.localizedDescription)"
        }
        isExporting = false
    }

    private func exportParentWindow() -> NSWindow? {
        resolveSavePanelWindow(
            presentingWindow: presentingWindowProvider(),
            keyWindow: NSApplication.shared.keyWindow,
            mainWindow: NSApplication.shared.mainWindow
        )
    }

    private static func requestStatusItemRefresh() {
        NotificationCenter.default.post(name: .macUsageMeterStatusItemNeedsRefresh, object: nil)
    }
}
