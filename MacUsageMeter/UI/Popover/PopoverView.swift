import SwiftUI
import Charts

/// G-002 ポップオーバー画面 (第5.3節)
///
/// メニューバークリックで表示。現在値、ミニグラフ、状態を表示する。
///
/// レイアウト仕様 (5.3.1):
/// - 幅: 320pt 固定
/// - 最小高さ: 280pt
/// - 最大高さ: 480pt
/// - 外側マージン: 12pt
/// - セクション間スペーシング: 8pt
/// - ヘッダ/フッタはスクロール外に固定
struct PopoverView: View {

    // MARK: - Properties

    @ObservedObject var viewModel: PopoverViewModel

    /// 「詳細を見る」ボタンアクション
    var onShowDetail: (() -> Void)?

    /// エラー状態画面を開くアクション
    var onShowError: ((StateCode) -> Void)?

    /// 設定画面を開くアクション (G-004)
    var onShowSettings: (() -> Void)?

    /// アプリ終了アクション
    var onQuit: (() -> Void)?

    // MARK: - Layout Constants

    private static let width: CGFloat = 320
    private static let minHeight: CGFloat = 280
    private static let maxHeight: CGFloat = 480
    private static let outerMargin: CGFloat = 12
    private static let sectionSpacing: CGFloat = 8

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダ (スクロール外)
            headerSection()

            Divider()

            // コンテンツ領域 (スクロール対象)
            ScrollView {
                VStack(spacing: Self.sectionSpacing) {
                    currentValuesSection()
                    Divider()
                    costSection()
                    Divider()
                    monthlyCostSection()
                    Divider()
                    miniGraphSection()
                    Divider()
                    statusSection()
                }
                .padding(Self.outerMargin)
            }

            Divider()

            // フッタ (スクロール外)
            footerSection()
        }
        .frame(width: Self.width)
        .frame(minHeight: Self.minHeight, maxHeight: Self.maxHeight)
        .accessibilityIdentifier("popoverView")
    }

    // MARK: - Header

    private func headerSection() -> some View {
        HStack {
            Image(systemName: "bolt.fill")
                .font(.title3)
            Text("Mac Usage Meter")
                .font(.headline)
            Spacer()
            if let text = viewModel.lastUpdatedText {
                Text(text)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityLabel("最終更新 \(text)")
            }
        }
        .padding(.horizontal, Self.outerMargin)
        .padding(.vertical, 8)
    }

    // MARK: - Subviews

    /// 現在値セクション
    private func currentValuesSection() -> some View {
        VStack(spacing: 6) {
            // 現在電力
            HStack {
                Label("現在の電力", systemImage: "bolt.fill")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                if let watts = viewModel.currentWatts {
                    Text(String(format: "%.1f W", watts))
                        .font(.system(.title2, design: .rounded).bold())
                        .accessibilityLabel("現在の消費電力 \(String(format: "%.1f", watts))ワット")
                } else {
                    Text("読み込み中")
                        .font(.title2)
                        .foregroundColor(.secondary)
                        .accessibilityLabel("現在の消費電力 読み込み中")
                }
            }

            // 直近平均電力
            HStack {
                Label("直近1時間平均", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                if let avg = viewModel.recentAverageWatts {
                    Text(String(format: "%.1f W", avg))
                        .font(.body.monospacedDigit())
                        .accessibilityLabel("直近1時間の平均電力 \(String(format: "%.1f", avg))ワット")
                } else {
                    Text("\u{2014}")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .accessibilityLabel("直近1時間の平均電力 未算出")
                }
            }

            // Wi-Fi 使用量
            HStack {
                Label("今日の Wi-Fi", systemImage: "wifi")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(viewModel.todayWifiUsageText)
                    .font(.body.monospacedDigit())
                    .accessibilityLabel("今日のWi-Fi使用量 \(viewModel.todayWifiUsageText)")
            }
        }
    }

    /// 概算料金セクション
    private func costSection() -> some View {
        VStack(spacing: 6) {
            // 概算電気代
            HStack {
                Label("概算電気代(税別)", systemImage: "yensign.circle")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                if let kwh = viewModel.todayPowerKwh {
                    Text(String(format: "%.4f kWh", kwh))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                Text(viewModel.formatCostYen(viewModel.todayPowerCostYen))
                    .font(.body.monospacedDigit())
            }

            // 概算通信費
            HStack {
                Label("概算通信費(税別)", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(viewModel.formatCostYen(viewModel.todayNetworkCostYen))
                    .font(.body.monospacedDigit())
            }
        }
    }

    /// 月次概算料金セクション (monthly_reset_day 基準)
    private func monthlyCostSection() -> some View {
        VStack(spacing: 6) {
            // 期間ラベル
            HStack {
                Text("月次概算 (\(viewModel.monthlyPeriodLabel))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }

            // 月次概算電気代
            HStack {
                Label("電気代(税別)", systemImage: "yensign.circle")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                if let kwh = viewModel.monthlyPowerKwh {
                    Text(String(format: "%.4f kWh", kwh))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                Text(viewModel.formatCostYen(viewModel.monthlyPowerCostYen))
                    .font(.body.monospacedDigit())
            }

            // 月次概算通信費
            HStack {
                Label("通信費(税別)", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                if let gb = viewModel.monthlyWifiGb {
                    Text(String(format: "%.2f GB", gb))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                Text(viewModel.formatCostYen(viewModel.monthlyNetworkCostYen))
                    .font(.body.monospacedDigit())
            }

            Divider()

            // 月次合計
            HStack {
                Label("合計(税別)", systemImage: "sum")
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                Spacer()
                Text(viewModel.formatCostYen(viewModel.monthlyTotalCostYen))
                    .font(.body.bold().monospacedDigit())
            }
        }
    }

    /// ミニグラフセクション (直近1時間の電力推移)
    private func miniGraphSection() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("直近1時間の電力推移")
                .font(.caption)
                .foregroundColor(.secondary)

            if viewModel.recentPowerSamples.isEmpty {
                Rectangle()
                    .fill(Color.secondary.opacity(0.1))
                    .frame(height: 60)
                    .overlay(
                        Text("データなし")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    )
            } else {
                Chart(viewModel.recentPowerSamples.filter { $0.avgWatts != nil }) { sample in
                    LineMark(
                        x: .value("時刻", Date(timeIntervalSince1970: Double(sample.capturedAtMs) / 1000.0)),
                        y: .value("電力 (W)", sample.avgWatts ?? 0)
                    )
                    .foregroundStyle(Color.blue.gradient)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisValueLabel(format: .dateTime.hour().minute())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 60)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(miniGraphAccessibilityLabel)
    }

    private var miniGraphAccessibilityLabel: String {
        if let avg = viewModel.recentAverageWatts {
            return "直近1時間の電力推移グラフ、平均\(String(format: "%.1f", avg))ワット"
        }
        return "直近1時間の電力推移グラフ、データなし"
    }

    /// ステータスセクション
    private func statusSection() -> some View {
        VStack(spacing: 8) {
            // 状態メッセージ
            HStack {
                statusIcon
                Text(viewModel.statusMessage)
                    .font(.subheadline)
                    .accessibilityLabel("状態: \(viewModel.statusMessage)")
                Spacer()
            }

            // ボタン
            HStack(spacing: 12) {
                Button(action: { onShowDetail?() }) {
                    Label("詳細を見る", systemImage: "chart.bar.xaxis")
                        .font(.subheadline)
                }
                .accessibilityIdentifier("showDetailButton")
                .accessibilityLabel("詳細画面を開く")

                if viewModel.shouldShowRetryButton {
                    Button(action: {
                        viewModel.retry()
                    }) {
                        Label("再試行", systemImage: "arrow.clockwise")
                            .font(.subheadline)
                    }
                    .accessibilityLabel("計測を再試行")
                }

                Spacer()
            }
        }
    }

    /// 状態に応じたアイコン
    @ViewBuilder
    private var statusIcon: some View {
        switch viewModel.collectorState {
        case .normal:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.subheadline)
        case .starting:
            ProgressView()
                .controlSize(.small)
        case .degraded:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
                .font(.subheadline)
        case .limitedReady:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
                .font(.subheadline)
        case .notReady:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(.subheadline)
        }
    }

    /// フッタ: 免責テキストと設定ボタン
    private func footerSection() -> some View {
        HStack {
            Text("概算値であり、実際の請求額とは異なります")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            Button(action: { onShowSettings?() }) {
                Image(systemName: "gearshape")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("showSettingsButton")
            .accessibilityLabel("設定を開く")

            Button(action: { onQuit?() }) {
                Image(systemName: "power")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("quitButton")
            .accessibilityLabel("終了")
        }
        .padding(.horizontal, Self.outerMargin)
        .padding(.vertical, 6)
    }
}
