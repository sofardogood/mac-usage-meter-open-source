import Foundation

/// アプリ設定 (app_settings テーブル対応)
///
/// key-value 形式で設定を保存する。
/// 各キーは value_text / value_number / value_bool のいずれか1つのカラムのみを使用し、他は NULL。
struct AppSetting: Codable, Sendable, Identifiable {
    /// 設定キー (PRIMARY KEY)
    let key: String

    /// テキスト値 (enum/string 型設定)
    let valueText: String?

    /// 数値 (数値型設定)
    let valueNumber: Double?

    /// ブール値 (0/1)
    let valueBool: Int?

    /// 更新時刻 (UTC Epoch ms)
    let updatedAtMs: Int64

    // MARK: - Identifiable

    var id: String { key }

    // MARK: - Known Keys

    /// 設定キー定義 (第5.4節)
    enum Key: String, CaseIterable, Sendable {
        /// ログイン時に起動 (bool, 初期値: true)
        case launchAtLoginEnabled = "launch_at_login_enabled"

        /// 電力単価 円/kWh、税別 (decimal, 初期値: 31.0, 範囲: 0.00〜999.99)
        case electricityUnitPriceYen = "electricity_unit_price_yen"

        /// 通信契約モデル (enum: fixed/metered/capped_metered, 初期値: fixed)
        case networkTariffModel = "network_tariff_model"

        /// 固定月額 円 (decimal, 初期値: 0, 範囲: 0.00〜999999.99)
        case monthlyFeeYen = "monthly_fee_yen"

        /// GB 単価 円 (decimal, 初期値: 0, 範囲: 0.00〜9999.99)
        case pricePerGbYen = "price_per_gb_yen"

        /// 月額上限 円 (decimal, 初期値: 0, 範囲: 0.00〜999999.99)
        case maxMonthlyFeeYen = "max_monthly_fee_yen"

        /// 電力採取間隔 秒 (int, 初期値: 60, 範囲: 30〜300)
        case powerSamplingIntervalSec = "power_sampling_interval_sec"

        /// Wi-Fi 採取間隔 秒 (int, 初期値: 10, 範囲: 5〜60)
        case wifiSamplingIntervalSec = "wifi_sampling_interval_sec"

        /// 保持期間 日 (int, 初期値: 90, 範囲: 7〜365)
        case retentionDays = "retention_days"

        /// デバッグ採取保存 (bool, 初期値: false)
        case debugCaptureEnabled = "debug_capture_enabled"

        /// ログレベル (enum: debug/info/warn/error, 初期値: info)
        case logLevel = "log_level"

        /// 月次リセット日 (int, 初期値: 1, 範囲: 1〜28)
        case monthlyResetDay = "monthly_reset_day"

        /// セットアップ完了日時 (number, Epoch ms)
        case setupCompletedAt = "setup_completed_at"
    }
}
