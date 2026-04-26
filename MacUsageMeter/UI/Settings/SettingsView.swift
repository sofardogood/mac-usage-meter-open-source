import SwiftUI

/// G-004 設定画面 (第5.4節)
///
/// 料金設定、採取間隔、保持期間、診断リンク。
/// 設定変更は保存時にバリデーションを実施し、Collector は非同期で設定再読込する。
struct SettingsView: View {

    // MARK: - ViewModel

    @ObservedObject var viewModel: SettingsViewModel

    // MARK: - Body

    var body: some View {
        Form {
            // 一般
            Section(header: Text("一般")) {
                Toggle(isOn: $viewModel.launchAtLoginEnabled) {
                    Text("ログイン時に起動")
                }
                .accessibilityLabel("ログイン時に起動、\(viewModel.launchAtLoginEnabled ? "オン" : "オフ")")
            }

            // 料金設定
            tariffSection()

            // 採取設定
            samplingSection()

            // データ管理
            dataManagementSection()

            // 診断
            diagnosticsSection()

            // 保存ボタン
            Section {
                HStack {
                    Spacer()
                    Button("設定を保存") {
                        viewModel.save()
                    }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("saveSettingsButton")
                    .accessibilityLabel("設定を保存")
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 500)
        .accessibilityIdentifier("settingsView")
        .onAppear {
            viewModel.loadSettings()
        }
        .overlay(alignment: .top) {
            // トースト通知
            if viewModel.showSaveToast {
                toastView(message: "設定を保存しました", color: .green)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.3), value: viewModel.showSaveToast)
            }
            if let error = viewModel.saveErrorMessage {
                toastView(message: error, color: .red)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.3), value: viewModel.saveErrorMessage)
            }
        }
    }

    // MARK: - Sections

    /// 料金設定セクション
    private func tariffSection() -> some View {
        Section(header: Text("料金設定")) {
            // 電力単価
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("電力単価 (円/kWh、税別)")
                    Spacer()
                    TextField("31.0", text: $viewModel.electricityUnitPriceYen)
                        .frame(width: 100)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("electricityUnitPriceField")
                }
                .accessibilityLabel("電力単価、1キロワットアワーあたりの円、現在\(viewModel.electricityUnitPriceYen)円")
                if let error = viewModel.validationErrors["electricityUnitPriceYen"] {
                    inlineError(error)
                }
            }

            // 通信契約モデル
            Picker("通信契約モデル", selection: $viewModel.networkTariffModel) {
                Text("固定月額").tag(TariffModel.fixed)
                Text("従量課金").tag(TariffModel.metered)
                Text("上限付き従量").tag(TariffModel.cappedMetered)
            }
            .accessibilityLabel("通信契約モデル、現在\(tariffModelLabel)")

            // 固定月額
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("固定月額 (円)")
                    Spacer()
                    TextField("0", text: $viewModel.monthlyFeeYen)
                        .frame(width: 120)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .disabled(!viewModel.isMonthlyFeeEnabled)
                }
                .opacity(viewModel.isMonthlyFeeEnabled ? 1.0 : 0.5)
                if let error = viewModel.validationErrors["monthlyFeeYen"] {
                    inlineError(error)
                }
            }

            // GB 単価
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("GB 単価 (円)")
                    Spacer()
                    TextField("0", text: $viewModel.pricePerGbYen)
                        .frame(width: 120)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .disabled(!viewModel.isPricePerGbEnabled)
                }
                .opacity(viewModel.isPricePerGbEnabled ? 1.0 : 0.5)
                if let error = viewModel.validationErrors["pricePerGbYen"] {
                    inlineError(error)
                }
            }

            // 月額上限
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("月額上限 (円)")
                    Spacer()
                    TextField("0", text: $viewModel.maxMonthlyFeeYen)
                        .frame(width: 120)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .disabled(!viewModel.isMaxMonthlyFeeEnabled)
                }
                .opacity(viewModel.isMaxMonthlyFeeEnabled ? 1.0 : 0.5)
                if let error = viewModel.validationErrors["maxMonthlyFeeYen"] {
                    inlineError(error)
                }
            }
        }
    }

    /// 採取設定セクション
    private func samplingSection() -> some View {
        Section(header: Text("採取設定")) {
            VStack(alignment: .leading, spacing: 2) {
                Stepper(
                    "電力採取間隔: \(viewModel.powerSamplingIntervalSec)秒",
                    value: $viewModel.powerSamplingIntervalSec,
                    in: 1...300,
                    step: 10
                )
                if let error = viewModel.validationErrors["powerSamplingIntervalSec"] {
                    inlineError(error)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Stepper(
                    "Wi-Fi 採取間隔: \(viewModel.wifiSamplingIntervalSec)秒",
                    value: $viewModel.wifiSamplingIntervalSec,
                    in: 1...60,
                    step: 5
                )
                if let error = viewModel.validationErrors["wifiSamplingIntervalSec"] {
                    inlineError(error)
                }
            }
        }
    }

    /// データ管理セクション
    private func dataManagementSection() -> some View {
        Section(header: Text("データ管理")) {
            VStack(alignment: .leading, spacing: 2) {
                Stepper(
                    "保持期間: \(viewModel.retentionDays)日",
                    value: $viewModel.retentionDays,
                    in: 7...365,
                    step: 1
                )
                .accessibilityLabel("データ保持期間、現在\(viewModel.retentionDays)日")
                if let error = viewModel.validationErrors["retentionDays"] {
                    inlineError(error)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Stepper(
                    "月次リセット日: 毎月\(viewModel.monthlyResetDay)日",
                    value: $viewModel.monthlyResetDay,
                    in: 1...28,
                    step: 1
                )
                if let error = viewModel.validationErrors["monthlyResetDay"] {
                    inlineError(error)
                }
            }
        }
    }

    /// 診断セクション
    private func diagnosticsSection() -> some View {
        Section(header: Text("診断")) {
            Toggle("デバッグ採取保存", isOn: $viewModel.debugCaptureEnabled)

            Picker("ログレベル", selection: $viewModel.logLevel) {
                Text("Debug").tag("debug")
                Text("Info").tag("info")
                Text("Warn").tag("warn")
                Text("Error").tag("error")
            }

            Button("診断情報を表示") {
                // 診断画面への遷移 (ErrorStateView 経由)
            }
            .accessibilityLabel("診断情報を表示")
        }
    }

    // MARK: - Helpers

    /// インラインバリデーションエラー表示
    private func inlineError(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.red)
                .font(.caption)
            Text(message)
                .font(.caption)
                .foregroundColor(.red)
        }
    }

    /// トースト通知ビュー
    private func toastView(message: String, color: Color) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(color.opacity(0.9))
            .cornerRadius(8)
            .padding(.top, 8)
    }

    /// 通信契約モデルのラベル
    private var tariffModelLabel: String {
        switch viewModel.networkTariffModel {
        case .fixed: return "固定月額"
        case .metered: return "従量課金"
        case .cappedMetered: return "上限付き従量"
        }
    }
}
