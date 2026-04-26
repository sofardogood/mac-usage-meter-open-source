import SwiftUI
import Charts

/// G-003 詳細画面 History (第5.6節)
///
/// 履歴グラフ、CSV エクスポート。
/// 期間別 (1時間, 24時間, 7日, 30日, 90日) の推移表示。
struct DetailView: View {

    // MARK: - Properties

    /// 表示期間
    enum Period: String, CaseIterable, Sendable {
        case oneHour = "1時間"
        case twentyFourHours = "24時間"
        case sevenDays = "7日"
        case thirtyDays = "30日"
        case ninetyDays = "90日"
    }

    /// 選択中の表示期間
    @State private var selectedPeriod: Period = .twentyFourHours

    /// 選択中のタブ
    @State private var selectedTab: Tab = .history

    enum Tab: String, CaseIterable {
        case history = "History"
        case export = "Export"
    }

    @ObservedObject var viewModel: DetailViewModel

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // タブセレクタ
            Picker("タブ", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            switch selectedTab {
            case .history:
                historyTab()
            case .export:
                exportTab()
            }
        }
        .frame(minWidth: 600, minHeight: 450)
        .onAppear {
            viewModel.loadData(for: selectedPeriod)
        }
        .onChange(of: selectedPeriod) { newValue in
            viewModel.loadData(for: newValue)
        }
    }

    // MARK: - History Tab

    private func historyTab() -> some View {
        VStack(spacing: 12) {
            // 期間セレクタ
            periodSelector()

            if viewModel.isLoading {
                Spacer()
                ProgressView("データを読み込み中...")
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        // 電力グラフ
                        powerChart()

                        Divider()

                        // Wi-Fi グラフ
                        wifiChart()
                    }
                    .padding()
                }
            }
        }
    }

    // MARK: - Subviews

    /// 期間セレクタ
    private func periodSelector() -> some View {
        Picker("表示期間", selection: $selectedPeriod) {
            ForEach(Period.allCases, id: \.self) { period in
                Text(period.rawValue).tag(period)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .accessibilityLabel("表示期間の選択、現在\(selectedPeriod.rawValue)")
    }

    /// 電力グラフ
    private func powerChart() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("電力")
                    .font(.headline)
                Spacer()
                if let avg = viewModel.averagePowerWatts {
                    Text("平均: \(String(format: "%.1f", avg)) W")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                if let max = viewModel.maxPowerWatts {
                    Text("最大: \(String(format: "%.1f", max)) W")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            if isRawPeriod {
                // 折れ線グラフ (1時間/24時間)
                if viewModel.powerSamples.isEmpty {
                    emptyChartPlaceholder("電力データがありません")
                } else {
                    Chart(viewModel.powerSamples.filter { $0.avgWatts != nil }) { sample in
                        LineMark(
                            x: .value("時刻", Date(timeIntervalSince1970: Double(sample.capturedAtMs) / 1000.0)),
                            y: .value("電力 (W)", sample.avgWatts ?? 0)
                        )
                        .foregroundStyle(Color.blue.gradient)
                        .interpolationMethod(.catmullRom)
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 6)) { value in
                            AxisValueLabel(format: .dateTime.hour().minute())
                            AxisGridLine()
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading)
                    }
                    .frame(height: 180)
                }
            } else {
                // 棒グラフ (7日/30日/90日)
                if viewModel.dailyRollups.isEmpty {
                    emptyChartPlaceholder("電力データがありません")
                } else {
                    Chart(viewModel.dailyRollups) { rollup in
                        BarMark(
                            x: .value("日付", rollup.dateLocal),
                            y: .value("電力量 (kWh)", rollup.powerKwh ?? 0)
                        )
                        .foregroundStyle(Color.blue.gradient)
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: min(viewModel.dailyRollups.count, 10))) { _ in
                            AxisValueLabel(orientation: .vertical)
                            AxisGridLine()
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading)
                    }
                    .frame(height: 180)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(powerChartAccessibilityLabel)
    }

    /// Wi-Fi グラフ
    private func wifiChart() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Wi-Fi 使用量")
                    .font(.headline)
                Spacer()
                Text("合計: \(viewModel.totalWifiUsageText)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if isRawPeriod {
                // 積み上げ棒グラフ (24時間)
                if viewModel.wifiSamples.isEmpty {
                    emptyChartPlaceholder("Wi-Fi データがありません")
                } else {
                    Chart(viewModel.wifiSamples) { sample in
                        BarMark(
                            x: .value("時刻", Date(timeIntervalSince1970: Double(sample.capturedAtMs) / 1000.0)),
                            y: .value("送信 (KB)", Double(sample.sentBytesDelta) / 1000.0)
                        )
                        .foregroundStyle(by: .value("種別", "送信"))

                        BarMark(
                            x: .value("時刻", Date(timeIntervalSince1970: Double(sample.capturedAtMs) / 1000.0)),
                            y: .value("受信 (KB)", Double(sample.recvBytesDelta) / 1000.0)
                        )
                        .foregroundStyle(by: .value("種別", "受信"))
                    }
                    .chartForegroundStyleScale([
                        "送信": Color.orange,
                        "受信": Color.green
                    ])
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 6)) { value in
                            AxisValueLabel(format: .dateTime.hour().minute())
                            AxisGridLine()
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading)
                    }
                    .frame(height: 180)
                }
            } else {
                // 棒グラフ (7日/30日/90日)
                if viewModel.dailyRollups.isEmpty {
                    emptyChartPlaceholder("Wi-Fi データがありません")
                } else {
                    Chart(viewModel.dailyRollups) { rollup in
                        BarMark(
                            x: .value("日付", rollup.dateLocal),
                            y: .value("使用量 (GB)", rollup.wifiGb ?? 0)
                        )
                        .foregroundStyle(Color.green.gradient)
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: min(viewModel.dailyRollups.count, 10))) { _ in
                            AxisValueLabel(orientation: .vertical)
                            AxisGridLine()
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading)
                    }
                    .frame(height: 180)
                }
            }

            Text("LAN 通信を含む参考値です")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(selectedPeriod.rawValue)のWi-Fi使用量グラフ、合計\(viewModel.totalWifiUsageText)")
    }

    // MARK: - Export Tab

    private func exportTab() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CSV エクスポート")
                .font(.headline)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 14) {
                exportField(label: "出力種別") {
                    Picker("出力種別", selection: $viewModel.exportType) {
                        Text("電力サンプル (raw)").tag(CSVExporter.ExportType.rawPower)
                        Text("Wi-Fi サンプル (raw)").tag(CSVExporter.ExportType.rawWifi)
                        Text("日次ロールアップ").tag(CSVExporter.ExportType.dailyRollup)
                    }
                    .labelsHidden()
                    .frame(width: 240, alignment: .leading)
                }

                exportField(label: "開始日") {
                    DatePicker("開始日", selection: $viewModel.exportDateFrom, displayedComponents: .date)
                        .labelsHidden()
                        .frame(width: 180, alignment: .leading)
                }

                exportField(label: "終了日") {
                    DatePicker("終了日", selection: $viewModel.exportDateTo, displayedComponents: .date)
                        .labelsHidden()
                        .frame(width: 180, alignment: .leading)
                }

                HStack {
                    Spacer()
                    Button(action: { viewModel.exportCSV() }) {
                        Label("CSV ファイルに書き出す", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isExporting)
                    .accessibilityLabel("CSVファイルに書き出す")
                    .accessibilityIdentifier("csvExportButton")
                    Spacer()
                }
                .padding(.top, 8)

                if let message = viewModel.exportResultMessage {
                    HStack {
                        if message.contains("完了") {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                        }
                        Text(message)
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal)

            Spacer()

            Text("出力形式: UTF-8 (BOM 付き)、CRLF 改行、ヘッダー行あり")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
    }

    private func exportField<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 72, alignment: .leading)
            content()
            Spacer()
        }
    }

    // MARK: - Helpers

    private var isRawPeriod: Bool {
        selectedPeriod == .oneHour || selectedPeriod == .twentyFourHours
    }

    private func emptyChartPlaceholder(_ message: String) -> some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.05))
            .frame(height: 180)
            .overlay(
                VStack {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.largeTitle)
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            )
            .cornerRadius(8)
    }

    private var powerChartAccessibilityLabel: String {
        var parts = ["\(selectedPeriod.rawValue)の電力推移グラフ"]
        if let avg = viewModel.averagePowerWatts {
            parts.append("平均\(String(format: "%.1f", avg))ワット")
        }
        if let max = viewModel.maxPowerWatts {
            parts.append("最大\(String(format: "%.1f", max))ワット")
        }
        return parts.joined(separator: "、")
    }
}
