import Foundation
import Combine
import AppKit

/// メニューバーの ViewModel (G-001)
///
/// NSStatusItem のテキスト/アイコン更新ロジックを担当する。
/// 仕様書 5.2 の4状態に対応。
@MainActor
final class MenuBarViewModel: ObservableObject {

    /// 表示状態
    enum DisplayState: Sendable {
        /// 通常表示: 電力値と通信量
        case normal(watts: Double, wifiText: String)
        /// 重大エラー
        case error
        /// 縮退 (アイコンのみ)
        case compact
    }

    // MARK: - Published Properties

    /// 現在の表示状態
    @Published var displayState: DisplayState = .compact

    /// ツールチップテキスト
    @Published var tooltipText: String = "Mac Usage Meter"

    // MARK: - Dependencies

    private let collectorController: CollectorController
    private let databaseManager: DatabaseManager
    private var timerCancellable: AnyCancellable?

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

    /// 表示を更新する
    ///
    /// 状態に関わらず、DB にデータがあれば常に電力値と Wi-Fi 通信量を表示する。
    func refresh() {
        Task {
            let (latestWatts, wifiText) = await Task.detached { [databaseManager] in
                let watts = (try? databaseManager.fetchLatestSuccessPowerSample())?.avgWatts
                let wifi = Self.fetchTodayWifiUsageText(databaseManager: databaseManager)
                return (watts, wifi)
            }.value

            let watts = latestWatts ?? 0
            displayState = .normal(watts: watts, wifiText: wifiText)
            tooltipText = buildNormalTooltip(watts: watts)
        }
    }

    // MARK: - Status Item Update

    /// NSStatusItem を更新する
    func updateStatusItem(_ statusItem: NSStatusItem) {
        guard let button = statusItem.button else { return }

        switch displayState {
        case .normal(let watts, let wifiText):
            let wattsStr = String(format: "%.1fW", watts)
            updateButton(button, image: Self.boltIcon, title: Self.boltIcon == nil ? "⚡ \(wattsStr) / \(wifiText)" : " \(wattsStr) / \(wifiText)")

        case .error:
            updateButton(button, image: Self.warnIcon, title: Self.warnIcon == nil ? "⚠ Check" : " Check")

        case .compact:
            updateButton(button, image: Self.boltIcon, title: Self.boltIcon == nil ? "⚡" : "")
        }

        button.toolTip = tooltipText
    }

    private func updateButton(_ button: NSStatusBarButton, image: NSImage?, title: String) {
        if button.image !== image {
            button.image = image
        }
        if button.title != title {
            button.title = title
        }
    }

    private static let iconSize = NSSize(width: 18, height: 18)
    private static let boltIcon = makeIcon(systemName: "bolt.fill", size: iconSize)
    private static let warnIcon = makeIcon(systemName: "exclamationmark.triangle.fill", size: iconSize)

    /// SF Symbol アイコンを指定サイズのテンプレート画像として返す
    private static func makeIcon(systemName: String, size: NSSize) -> NSImage? {
        guard let img = NSImage(systemSymbolName: systemName, accessibilityDescription: nil) else { return nil }
        img.size = size
        img.isTemplate = true
        return img
    }

    // MARK: - Private

    /// 今日の Wi-Fi 累計バイト数を DB から取得してフォーマットする (メインスレッド外から呼び出し可能)
    private nonisolated static func fetchTodayWifiUsageText(databaseManager: DatabaseManager) -> String {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let startOfDayMs = Int64(startOfDay.timeIntervalSince1970 * 1000)
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        if let totalBytes = try? databaseManager.fetchDailyWifiTotalBytes(fromMs: startOfDayMs, toMs: nowMs) {
            return PopoverViewModel.formatBytes(totalBytes)
        }
        return "0 B"
    }

    private func buildNormalTooltip(watts: Double) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timeStr = formatter.string(from: Date())
        return "Last updated: \(timeStr)"
    }
}
