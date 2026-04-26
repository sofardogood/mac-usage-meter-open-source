import SwiftUI

/// G-005 初回セットアップ (第5.5節)
///
/// ウィザード形式の初期設定。5ステップで構成。
/// 初回起動時、または setup_completed_at が未設定のときに表示する。
struct SetupView: View {

    // MARK: - Properties

    @ObservedObject var viewModel: SetupViewModel

    /// セットアップ完了時のコールバック
    var onComplete: (() -> Void)?

    /// 総ステップ数
    static let totalSteps = 5

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // ステップインジケータ
            stepIndicator()
                .padding(.top, 16)
                .padding(.bottom, 8)

            Divider()

            // ステップコンテンツ
            Group {
                switch viewModel.currentStep {
                case 1: overviewStep()
                case 2: helperRegistrationStep()
                case 3: tariffSettingsStep()
                case 4: testSamplingStep()
                case 5: completionStep()
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)

            Divider()

            // ナビゲーションボタン
            navigationButtons()
                .padding(16)
        }
        .frame(minWidth: 480, minHeight: 500)
        .accessibilityIdentifier("setupView")
    }

    // MARK: - Steps

    /// ステップ 1: 概要説明
    private func overviewStep() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Mac Usage Meter へようこそ")
                .font(.title2.bold())
                .accessibilityIdentifier("setupWelcomeTitle")

            Text("このアプリは、Mac の消費電力と Wi-Fi 使用量を継続的に記録し、概算の料金を表示します。")
                .font(.body)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("監視対象", systemImage: "bolt.fill")
                        .font(.subheadline.bold())
                    Text("消費電力（W / kWh）と Wi-Fi 通信量（バイト / GB）")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Divider()

                    Label("概算値の注意", systemImage: "info.circle")
                        .font(.subheadline.bold())
                    Text("表示される金額はユーザー設定に基づく概算値（税別）です。実際の請求額とは異なります。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Divider()

                    Label("必要な権限", systemImage: "lock.shield")
                        .font(.subheadline.bold())
                    Text("電力データの取得には管理者権限が必要です。次のステップで計測ヘルパーの登録を行います。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(4)
            }

            Spacer()
        }
    }

    /// ステップ 2: Helper 登録
    private func helperRegistrationStep() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("計測ヘルパーの登録")
                .font(.title2.bold())

            Text("電力データの取得には特権ヘルパーの登録が必要です。「登録」ボタンを押すと、macOS が管理者パスワードを要求します。")
                .font(.body)

            Spacer()

            VStack(spacing: 16) {
                switch viewModel.helperRegistrationState {
                case .notStarted:
                    Button(action: { viewModel.registerHelper() }) {
                        Label("計測ヘルパーを登録する", systemImage: "gearshape.2.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityLabel("計測ヘルパーを登録する")

                case .registering:
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("登録中...")
                    }

                case .registered:
                    Label("登録が完了しました", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.headline)

                case .failed(let message):
                    VStack(alignment: .leading, spacing: 8) {
                        Label("登録に失敗しました", systemImage: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.headline)
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack(spacing: 12) {
                            Button("再試行") {
                                viewModel.registerHelper()
                            }
                            .accessibilityLabel("計測ヘルパーの登録を再試行")

                            Button("スキップして続行") {
                                viewModel.goToNextStep()
                            }
                            .foregroundColor(.secondary)
                            .accessibilityLabel("ヘルパー登録をスキップ")
                        }
                        Text("スキップすると電力計測は無効になりますが、Wi-Fi 計測と画面の確認は可能です。")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Spacer()
        }
    }

    /// ステップ 3: 料金設定
    private func tariffSettingsStep() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("料金設定")
                .font(.title2.bold())

            Text("概算料金の計算に使用する情報を入力してください。設定は後から変更できます。")
                .font(.body)

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    // 電力単価
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("電力単価 (円/kWh、税別)")
                            Spacer()
                            TextField("31.0", text: $viewModel.electricityUnitPriceYen)
                                .frame(width: 100)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                        }
                        if let error = viewModel.tariffValidationErrors["electricityUnitPriceYen"] {
                            errorLabel(error)
                        }
                    }

                    Divider()

                    // 通信契約モデル
                    HStack {
                        Text("通信契約モデル")
                        Spacer()
                        Picker("", selection: $viewModel.networkTariffModel) {
                            Text("固定月額").tag(TariffModel.fixed)
                            Text("従量課金").tag(TariffModel.metered)
                            Text("上限付き従量").tag(TariffModel.cappedMetered)
                        }
                        .labelsHidden()
                        .frame(width: 160)
                    }

                    // 固定月額
                    if viewModel.networkTariffModel == .fixed || viewModel.networkTariffModel == .cappedMetered {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("固定月額 (円)")
                                Spacer()
                                TextField("0", text: $viewModel.monthlyFeeYen)
                                    .frame(width: 120)
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.trailing)
                            }
                            if let error = viewModel.tariffValidationErrors["monthlyFeeYen"] {
                                errorLabel(error)
                            }
                        }
                    }

                    // GB 単価
                    if viewModel.networkTariffModel == .metered || viewModel.networkTariffModel == .cappedMetered {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("GB 単価 (円)")
                                Spacer()
                                TextField("0", text: $viewModel.pricePerGbYen)
                                    .frame(width: 120)
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.trailing)
                            }
                            if let error = viewModel.tariffValidationErrors["pricePerGbYen"] {
                                errorLabel(error)
                            }
                        }
                    }

                    // 月額上限
                    if viewModel.networkTariffModel == .cappedMetered {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("月額上限 (円)")
                                Spacer()
                                TextField("0", text: $viewModel.maxMonthlyFeeYen)
                                    .frame(width: 120)
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.trailing)
                            }
                            if let error = viewModel.tariffValidationErrors["maxMonthlyFeeYen"] {
                                errorLabel(error)
                            }
                        }
                    }

                    Divider()

                    // ログイン時起動
                    Toggle("ログイン時に起動", isOn: $viewModel.launchAtLoginEnabled)
                }
                .padding(4)
            }
        }
    }

    /// ステップ 4: 試験採取
    private func testSamplingStep() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("試験採取")
                .font(.title2.bold())

            Text("データが正しく取得できるか確認します。「テスト実行」ボタンを押してください。")
                .font(.body)

            // テスト実行ボタン
            Button(action: { viewModel.runTestSampling() }) {
                Label("テスト実行", systemImage: "play.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isTestRunning)

            Spacer()

            // 電力テスト結果
            GroupBox {
                HStack {
                    testResultIcon(viewModel.testPowerResult)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("電力データ")
                            .font(.subheadline.bold())
                        Text(viewModel.testPowerMessage.isEmpty ? "未実行" : viewModel.testPowerMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }

            // Wi-Fi テスト結果
            GroupBox {
                HStack {
                    testResultIcon(viewModel.testWifiResult)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Wi-Fi データ")
                            .font(.subheadline.bold())
                        Text(viewModel.testWifiMessage.isEmpty ? "未実行" : viewModel.testWifiMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }

            Spacer()
        }
    }

    /// ステップ 5: 完了
    private func completionStep() -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)

            Text("セットアップ完了")
                .font(.title.bold())

            Text("Mac Usage Meter の設定が完了しました。メニューバーにアイコンが表示され、消費電力と Wi-Fi 使用量の記録が開始されます。")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 8) {
                summaryRow(icon: "bolt.fill", label: "電力計測",
                           status: viewModel.testPowerResult.isSuccess ? "有効" : "限定的（Wi-Fi のみ）")
                summaryRow(icon: "wifi", label: "Wi-Fi 計測",
                           status: viewModel.testWifiResult.isSuccess ? "有効" : "確認が必要です")
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(8)

            Text("設定はメニューバーアイコンから「設定」を開いていつでも変更できます。")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .onAppear {
            viewModel.completeSetup()
        }
    }

    // MARK: - Navigation

    /// ステップインジケータ
    private func stepIndicator() -> some View {
        HStack(spacing: 8) {
            ForEach(1...Self.totalSteps, id: \.self) { step in
                Circle()
                    .fill(step <= viewModel.currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 10, height: 10)

                if step < Self.totalSteps {
                    Rectangle()
                        .fill(step < viewModel.currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(height: 2)
                        .frame(maxWidth: 40)
                }
            }
        }
        .padding(.horizontal, 40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("セットアップ ステップ\(viewModel.currentStep)/\(Self.totalSteps)")
    }

    /// ナビゲーションボタン
    private func navigationButtons() -> some View {
        HStack {
            if viewModel.currentStep > 1 && viewModel.currentStep < Self.totalSteps {
                Button("戻る") {
                    viewModel.goToPreviousStep()
                }
                .accessibilityLabel("前のステップに戻る")
            }

            Spacer()

            if viewModel.currentStep < Self.totalSteps {
                Button("次へ") {
                    viewModel.goToNextStep()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canProceed)
                .accessibilityLabel("次のステップへ進む")
            } else {
                Button("完了") {
                    onComplete?()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("セットアップを完了する")
            }
        }
    }

    // MARK: - Helpers

    private var isTestRunning: Bool {
        if case .running = viewModel.testPowerResult { return true }
        if case .running = viewModel.testWifiResult { return true }
        return false
    }

    @ViewBuilder
    private func testResultIcon(_ result: SetupViewModel.TestResult) -> some View {
        switch result {
        case .notStarted:
            Image(systemName: "circle")
                .foregroundColor(.secondary)
        case .running:
            ProgressView()
                .controlSize(.small)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
        }
    }

    private func errorLabel(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.red)
                .font(.caption)
            Text(message)
                .font(.caption)
                .foregroundColor(.red)
        }
    }

    private func summaryRow(icon: String, label: String, status: String) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 20)
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(status)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}
