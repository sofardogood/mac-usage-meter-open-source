import Foundation

/// 日次ロールアップ (daily_rollups テーブル対応)
///
/// 生サンプルを日次に再集計した長期保存用データ。
/// 暦日 (00:00:00〜23:59:59 ローカル時刻) ベースで集計する。
struct DailyRollup: Codable, Sendable, Identifiable {
    /// 日付 (ローカル) "YYYY-MM-DD" 形式。PRIMARY KEY
    let dateLocal: String

    /// 電力量 (kWh)。欠測時は nil
    let powerKwh: Double?

    /// Wi-Fi 使用量 (GB, SI基準: 10^9 bytes)。欠測時は nil
    let wifiGb: Double?

    /// 電力料金 (円、税別)。欠測時は nil
    let powerCostYen: Double?

    /// 通信料金 (円、税別)。欠測時は nil
    let networkCostYen: Double?

    /// 電力 coverage ratio (0.0〜1.0)
    let coverageRatioPower: Double

    /// Wi-Fi coverage ratio (0.0〜1.0)
    let coverageRatioWifi: Double

    /// 電力サンプル数
    let sampleCountPower: Int

    /// Wi-Fi サンプル数
    let sampleCountWifi: Int

    /// 集計実行時刻 (UTC Epoch ms)
    let computedAtMs: Int64

    // MARK: - Identifiable

    var id: String { dateLocal }
}
