import SwiftUI
import AppKit

/// G-006 欠測/エラー状態画面 (第6.3節)
///
/// 原因、影響範囲、直近発生時刻、推奨アクション、再試行導線を提示する専用画面。
/// ポップオーバー (G-002)、ローカル通知、設定画面 (G-004) の診断リンクから遷移可能。
struct ErrorStateView: View {

    // MARK: - Properties

    /// 状態コード
    let stateCode: StateCode

    /// 発生時刻 (ローカル表記 yyyy-MM-dd HH:mm:ss)
    let occurredAt: String?

    /// 最終成功時刻 (ローカル表記)
    let lastSuccessAt: String?

    /// 内部エラーコード (debug_capture_enabled=true 時のみコピー可能)
    let internalErrorCode: String?

    /// デバッグモードかどうか
    let isDebugEnabled: Bool

    /// 再試行ボタンアクション
    var onRetry: (() -> Void)?

    /// セットアップ再開ボタンアクション
    var onRestartSetup: (() -> Void)?

    /// 設定を開くボタンアクション
    var onOpenSettings: (() -> Void)?

    /// ログを開くボタンアクション
    var onOpenLog: (() -> Void)?

    /// 閉じるボタンアクション
    var onDismiss: (() -> Void)?

    /// 追加のエラー (折りたたみ一覧用)
    var additionalStateCodes: [StateCode] = []

    /// 折りたたみ一覧の展開状態
    @State private var isAdditionalExpanded: Bool = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    // ヘッダ
                    headerSection()

                    Divider()

                    // 概要
                    summarySection()

                    Divider()

                    // 診断
                    diagnosticSection()

                    // 追加エラーの折りたたみ一覧
                    if !additionalStateCodes.isEmpty {
                        Divider()
                        additionalErrorsSection()
                    }

                    Divider()

                    // 操作
                    actionSection()
                }
                .padding(20)
            }

            Divider()

            // フッタ
            footerSection()
        }
        .frame(minWidth: 400, minHeight: 350)
    }

    // MARK: - Subviews

    /// ヘッダ: 状態アイコン + 状態タイトル
    private func headerSection() -> some View {
        VStack(spacing: 12) {
            // 状態アイコン
            Image(systemName: iconName)
                .font(.system(size: 48))
                .foregroundColor(iconColor())
                .accessibilityLabel("\(severityLabel)状態")

            // 状態タイトル
            Text(stateCode.userMessage)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
                .accessibilityLabel(stateCode.userMessage)
        }
        .frame(maxWidth: .infinity)
    }

    /// 概要セクション: 主メッセージ、発生時刻、最終成功時刻、影響範囲
    private func summarySection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // 主メッセージ
            Text(detailedDescription)
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // 発生時刻
            if let time = occurredAt {
                HStack {
                    Text("検知時刻:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(time)
                        .font(.subheadline.monospacedDigit())
                }
            }

            // 最終成功時刻
            if let time = lastSuccessAt {
                HStack {
                    Text("最終正常:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(time)
                        .font(.subheadline.monospacedDigit())
                }
            }

            // 影響範囲
            HStack {
                Text("影響範囲:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                affectedScopeTags
            }
        }
    }

    /// 影響範囲タグ
    @ViewBuilder
    private var affectedScopeTags: some View {
        let labels = affectedScopeLabels
        HStack(spacing: 4) {
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(4)
            }
        }
    }

    /// 診断セクション: 状態コード、内部エラーコード
    private func diagnosticSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("診断情報")
                .font(.subheadline.bold())

            HStack {
                Text("状態コード:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(stateCode.rawValue)
                    .font(.subheadline.monospacedDigit())
                    .textSelection(.enabled)
            }

            if isDebugEnabled, let code = internalErrorCode {
                HStack {
                    Text("内部コード:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(code)
                        .font(.subheadline.monospacedDigit())
                        .textSelection(.enabled)
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("エラーコードをコピー")
                }
            }
        }
    }

    /// 追加エラーの折りたたみ一覧
    private func additionalErrorsSection() -> some View {
        DisclosureGroup(
            "他のエラー (\(additionalStateCodes.count)件)",
            isExpanded: $isAdditionalExpanded
        ) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(additionalStateCodes, id: \.rawValue) { code in
                    HStack {
                        Image(systemName: iconNameForSeverity(code.severity))
                            .foregroundColor(colorForSeverity(code.severity))
                            .font(.subheadline)
                        VStack(alignment: .leading) {
                            Text(code.rawValue)
                                .font(.caption.monospacedDigit())
                            Text(code.userMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.top, 4)
        }
        .font(.subheadline)
    }

    /// 操作セクション
    private func actionSection() -> some View {
        VStack(spacing: 10) {
            // 再試行ボタン
            if stateCode.isRetryable, let onRetry = onRetry {
                Button(action: onRetry) {
                    Label("再試行", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityLabel("計測を再試行")
            }

            // セットアップ再開ボタン (M-001/M-002 時のみ)
            if stateCode == .authNotGranted || stateCode == .helperNotRegistered,
               let onRestartSetup = onRestartSetup {
                Button(action: onRestartSetup) {
                    Label("セットアップを再開", systemImage: "gearshape.2")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .accessibilityLabel("セットアップを再開する")
            }

            // 設定を開くボタン (常時表示)
            if let onOpenSettings = onOpenSettings {
                Button(action: onOpenSettings) {
                    Label("設定を開く", systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .accessibilityLabel("設定画面を開く")
            }

            // ログを開くボタン (debug_capture_enabled=true 時のみ)
            if isDebugEnabled, let onOpenLog = onOpenLog {
                Button(action: onOpenLog) {
                    Label("ログを開く", systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .accessibilityLabel("診断ログを開く")
            }
        }
    }

    /// フッタ: 閉じるボタン
    private func footerSection() -> some View {
        HStack {
            Spacer()
            Button("閉じる") {
                onDismiss?()
            }
            .accessibilityLabel("この画面を閉じる")
            .padding()
        }
    }

    // MARK: - Helpers

    /// 状態アイコンの色を返す
    private func iconColor() -> Color {
        switch stateCode.severity {
        case .fatal: return .red
        case .degraded: return .yellow
        case .informational: return .gray
        }
    }

    /// 状態に対応するアイコン名
    private var iconName: String {
        iconNameForSeverity(stateCode.severity)
    }

    private func iconNameForSeverity(_ severity: StateCode.Severity) -> String {
        switch severity {
        case .fatal: return "xmark.octagon.fill"
        case .degraded: return "exclamationmark.triangle.fill"
        case .informational: return "info.circle.fill"
        }
    }

    private func colorForSeverity(_ severity: StateCode.Severity) -> Color {
        switch severity {
        case .fatal: return .red
        case .degraded: return .yellow
        case .informational: return .gray
        }
    }

    /// severity の日本語ラベル
    private var severityLabel: String {
        switch stateCode.severity {
        case .fatal: return "重大エラー"
        case .degraded: return "警告"
        case .informational: return "情報"
        }
    }

    /// 影響範囲のラベル
    private var affectedScopeLabels: [String] {
        switch stateCode.affectedScope {
        case .power: return ["電力"]
        case .wifi: return ["Wi-Fi"]
        case .powerAndWifi: return ["電力", "Wi-Fi"]
        case .powerOrWifi: return ["電力またはWi-Fi"]
        case .storage: return ["保存"]
        }
    }

    /// 詳細説明テキスト
    private var detailedDescription: String {
        switch stateCode {
        case .authNotGranted:
            return "電力データの取得には管理者権限が必要です。セットアップを再開して権限を付与してください。"
        case .helperNotRegistered:
            return "計測ヘルパーが起動していないか、登録されていません。セットアップを再開するか、再試行してください。"
        case .powerMetricsUnsupported:
            return "この環境では powermetrics による電力データの取得がサポートされていません。Wi-Fi の使用量計測は引き続き利用できます。"
        case .initialDataPending:
            return "起動直後のため、最新のデータを取得中です。しばらくお待ちください。"
        case .powerDataFailure:
            return "電力データの取得または解析に失敗しました。一時的な問題の場合は自動的に回復します。"
        case .wifiInterfaceUnknown:
            return "Wi-Fi インターフェースを検出できません。ネットワークの接続状態を確認してください。"
        case .staleContinued:
            return "最新のデータが取得できておらず、表示されている値は古いものです。データ取得が再開されると自動的に回復します。"
        case .databaseFailure:
            return "データの保存先にアクセスできません。ディスクの空き容量やアクセス権限を確認してください。"
        case .wifiDisconnected:
            return "Wi-Fi に接続されていません。ネットワーク設定を確認してください。接続が復帰すると自動的に計測が再開されます。"
        }
    }
}
