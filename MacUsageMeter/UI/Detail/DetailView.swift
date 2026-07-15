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
        case oneHour = "1 Hour"
        case twentyFourHours = "24 Hours"
        case sevenDays = "7 Days"
        case thirtyDays = "30 Days"
        case ninetyDays = "90 Days"
    }

    /// 選択中の表示期間
    @State private var selectedPeriod: Period = .twentyFourHours

    /// 選択中のタブ
    @State private var selectedTab: Tab = .usage

    enum Tab: String, CaseIterable {
        case usage = "By Destination"
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
            case .usage:
                usageTab()
            case .history:
                historyTab()
            case .export:
                exportTab()
            }
        }
        .frame(minWidth: 600, minHeight: 450)
        .onAppear {
            viewModel.loadData(for: selectedPeriod)
            viewModel.loadUsageBreakdown(for: selectedPeriod)
        }
        .onChange(of: selectedPeriod) { newValue in
            viewModel.loadData(for: newValue)
            viewModel.loadUsageBreakdown(for: newValue)
        }
        .onChange(of: selectedTab) { tab in
            if tab == .usage {
                viewModel.loadUsageBreakdown(for: selectedPeriod)
            }
        }
    }

    // MARK: - History Tab

    private func historyTab() -> some View {
        VStack(spacing: 12) {
            // 期間セレクタ
            periodSelector()

            if viewModel.isLoading {
                Spacer()
                ProgressView("Loading data...")
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

    // MARK: - Usage Tab

    private func usageTab() -> some View {
        VStack(spacing: 12) {
            periodSelector()

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("Traffic by Destination", systemImage: "network")
                        .font(.headline)
                    Spacer()
                    Text(PopoverViewModel.formatBytes(viewModel.attributedUsageTotalBytes))
                        .font(.headline.monospacedDigit())
                }
                Text("Traffic is measured. Power is estimated by allocating the Mac-wide measured value by activity.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            if viewModel.usageDestinationSummaries.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No destination data yet")
                        .font(.headline)
                    Text("Tracking starts after the app launches. Existing Wi-Fi totals cannot be classified retroactively.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                }
                .padding()
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        usageCharts()

                        Divider()

                        Text("Destinations")
                            .font(.headline)
                        ForEach(viewModel.usageDestinationSummaries) { summary in
                            usageSummaryRow(summary)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private func usageCharts() -> some View {
        let summaries = Array(viewModel.usageDestinationSummaries.prefix(8))
        return VStack(alignment: .leading, spacing: 12) {
            Text("Traffic breakdown (Top 8)")
                .font(.headline)

            HStack(alignment: .top, spacing: 20) {
                UsagePieChart(summaries: summaries)
                    .frame(width: 190, height: 190)

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(summaries.enumerated()), id: \.element.id) { index, summary in
                        HStack(spacing: 6) {
                            Circle().fill(UsagePieChart.color(at: index)).frame(width: 9, height: 9)
                            Text("\(summary.applicationName) · \(summary.destinationLabel)")
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(PopoverViewModel.formatBytes(summary.totalBytes))
                                .font(.caption.monospacedDigit())
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("Traffic comparison (Top 8)")
                .font(.headline)
            Chart(summaries) { summary in
                BarMark(
                    x: .value("Destination", summary.applicationName),
                    y: .value("Traffic (GB)", Double(summary.totalBytes) / 1_000_000_000)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .annotation(position: .top) {
                    Text(PopoverViewModel.formatBytes(summary.totalBytes))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel(orientation: .vertical) }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 220)
        }
    }

    private func usageSummaryRow(_ summary: UsageDestinationSummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "app.dashed")
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.applicationName).font(.body.weight(.medium))
                Text(summary.destinationLabel).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(PopoverViewModel.formatBytes(summary.totalBytes)).font(.body.monospacedDigit())
                Text(summary.estimatedWatts.map { "Estimated \(String(format: "%.1f", $0)) W" } ?? "No power data")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - Subviews

    /// 期間セレクタ
    private func periodSelector() -> some View {
        Picker("Period", selection: $selectedPeriod) {
            ForEach(Period.allCases, id: \.self) { period in
                Text(period.rawValue).tag(period)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .accessibilityLabel("Period selection, currently \(selectedPeriod.rawValue)")
    }

    /// 電力グラフ
    private func powerChart() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Power")
                    .font(.headline)
                Spacer()
                if let avg = viewModel.averagePowerWatts {
                    Text("Average: \(String(format: "%.1f", avg)) W")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                if let max = viewModel.maxPowerWatts {
                    Text("Maximum: \(String(format: "%.1f", max)) W")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            if isRawPeriod {
                // 折れ線グラフ (1時間/24時間)
                if viewModel.powerSamples.isEmpty {
                    emptyChartPlaceholder("No power data")
                } else {
                    Chart(viewModel.powerSamples.filter { $0.avgWatts != nil }) { sample in
                        LineMark(
                            x: .value("Time", Date(timeIntervalSince1970: Double(sample.capturedAtMs) / 1000.0)),
                            y: .value("Power (W)", sample.avgWatts ?? 0)
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
                    emptyChartPlaceholder("No power data")
                } else {
                    Chart(viewModel.dailyRollups) { rollup in
                        BarMark(
                            x: .value("Date", rollup.dateLocal),
                            y: .value("Energy (kWh)", rollup.powerKwh ?? 0)
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
                Text("Wi-Fi Usage")
                    .font(.headline)
                Spacer()
                Text("Total: \(viewModel.totalWifiUsageText)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if isRawPeriod {
                // 積み上げ棒グラフ (24時間)
                if viewModel.wifiSamples.isEmpty {
                    emptyChartPlaceholder("No Wi-Fi data")
                } else {
                    Chart(viewModel.wifiSamples) { sample in
                        BarMark(
                            x: .value("Time", Date(timeIntervalSince1970: Double(sample.capturedAtMs) / 1000.0)),
                            y: .value("Sent (KB)", Double(sample.sentBytesDelta) / 1000.0)
                        )
                        .foregroundStyle(by: .value("Type", "Sent"))

                        BarMark(
                            x: .value("Time", Date(timeIntervalSince1970: Double(sample.capturedAtMs) / 1000.0)),
                            y: .value("Received (KB)", Double(sample.recvBytesDelta) / 1000.0)
                        )
                        .foregroundStyle(by: .value("Type", "Received"))
                    }
                    .chartForegroundStyleScale([
                        "Sent": Color.orange,
                        "Received": Color.green
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
                    emptyChartPlaceholder("No Wi-Fi data")
                } else {
                    Chart(viewModel.dailyRollups) { rollup in
                        BarMark(
                            x: .value("Date", rollup.dateLocal),
                            y: .value("Usage (GB)", rollup.wifiGb ?? 0)
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

            Text("Reference value; includes LAN traffic")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(selectedPeriod.rawValue)のWi-Fi使用量グラフ、合計\(viewModel.totalWifiUsageText)")
    }

    // MARK: - Export Tab

    private func exportTab() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CSV Export")
                .font(.headline)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 14) {
                exportField(label: "Export type") {
                    Picker("Export type", selection: $viewModel.exportType) {
                        Text("Power samples (raw)").tag(CSVExporter.ExportType.rawPower)
                        Text("Wi-Fi samples (raw)").tag(CSVExporter.ExportType.rawWifi)
                        Text("Daily rollups").tag(CSVExporter.ExportType.dailyRollup)
                    }
                    .labelsHidden()
                    .frame(width: 240, alignment: .leading)
                }

                exportField(label: "Start date") {
                    DatePicker("Start date", selection: $viewModel.exportDateFrom, displayedComponents: .date)
                        .labelsHidden()
                        .frame(width: 180, alignment: .leading)
                }

                exportField(label: "End date") {
                    DatePicker("End date", selection: $viewModel.exportDateTo, displayedComponents: .date)
                        .labelsHidden()
                        .frame(width: 180, alignment: .leading)
                }

                HStack {
                    Spacer()
                    Button(action: { viewModel.exportCSV() }) {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
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

            Text("UTF-8 with BOM, CRLF line endings, and a header row")
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
        var parts = ["Power chart for \(selectedPeriod.rawValue)"]
        if let avg = viewModel.averagePowerWatts {
            parts.append("average \(String(format: "%.1f", avg)) watts")
        }
        if let max = viewModel.maxPowerWatts {
            parts.append("maximum \(String(format: "%.1f", max)) watts")
        }
        return parts.joined(separator: "、")
    }
}

/// macOS 13 でも動作する利用先別のドーナツグラフ。
private struct UsagePieChart: View {
    let summaries: [UsageDestinationSummary]
    private let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .yellow]

    static func color(at index: Int) -> Color {
        [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .yellow][index % 8]
    }

    var body: some View {
        GeometryReader { proxy in
            let total = max(summaries.reduce(Int64(0)) { $0 + $1.totalBytes }, 1)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = min(proxy.size.width, proxy.size.height) / 2
            ZStack {
                ForEach(Array(summaries.enumerated()), id: \.element.id) { index, summary in
                    UsagePieSlice(
                        startFraction: fraction(before: index, total: total),
                        endFraction: fraction(before: index + 1, total: total)
                    )
                    .fill(palette[index % palette.count])
                }
                Circle().fill(Color(NSColor.windowBackgroundColor)).frame(width: radius * 1.05, height: radius * 1.05)
                VStack(spacing: 2) {
                    Text("Total").font(.caption).foregroundColor(.secondary)
                    Text(PopoverViewModel.formatBytes(total)).font(.caption.bold().monospacedDigit())
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .position(center)
        }
    }

    private func fraction(before index: Int, total: Int64) -> Double {
        Double(summaries.prefix(index).reduce(Int64(0)) { $0 + $1.totalBytes }) / Double(total)
    }
}

private struct UsagePieSlice: Shape {
    let startFraction: Double
    let endFraction: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let start = Angle.degrees(-90 + startFraction * 360)
        let end = Angle.degrees(-90 + endFraction * 360)
        var path = Path()
        path.move(to: center)
        path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        path.closeSubpath()
        return path
    }
}
