import Foundation

/// 通信契約モデル (第9章)
///
/// 通信料金の計算方式を定義する。
/// 日次 (daily_rollups.network_cost_yen) と月次の2段階で計算する。
enum TariffModel: String, Codable, CaseIterable, Sendable {
    /// 固定月額: monthly_fee_yen / 月の日数 (暦日で均等按分)
    case fixed

    /// 従量課金: wifi_gb * price_per_gb_yen
    case metered

    /// 上限付き従量: min(累計wifi_gb * price_per_gb_yen, max_monthly_fee_yen)
    /// 上限制御は月次側で行い、日次は単純従量で保存
    case cappedMetered = "capped_metered"
}

/// 料金計算に必要な設定値をまとめた構造体
struct TariffSettings: Codable, Sendable {
    /// 通信契約モデル
    let model: TariffModel

    /// 電力単価 (円/kWh、税別)。範囲: 0.00〜999.99
    let electricityUnitPriceYen: Double

    /// 固定月額 (円)。fixed / capped_metered 時に使用。範囲: 0.00〜999999.99
    let monthlyFeeYen: Double?

    /// GB 単価 (円)。metered / capped_metered 時に使用。範囲: 0.00〜9999.99
    let pricePerGbYen: Double?

    /// 月額上限 (円)。capped_metered 時のみ使用。範囲: 0.00〜999999.99
    let maxMonthlyFeeYen: Double?

    /// 月次リセット日 (1〜28)
    let monthlyResetDay: Int
}
