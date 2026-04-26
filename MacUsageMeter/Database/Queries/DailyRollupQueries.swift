import Foundation

/// 日次ロールアップ関連の SQL クエリ定義
enum DailyRollupQueries {

    /// 日次ロールアップを挿入または更新する
    static let upsert = """
    INSERT OR REPLACE INTO daily_rollups (
        date_local, power_kwh, wifi_gb, power_cost_yen, network_cost_yen,
        coverage_ratio_power, coverage_ratio_wifi,
        sample_count_power, sample_count_wifi, computed_at_ms
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """

    /// 指定期間の日次ロールアップを取得する (date_local 昇順)
    static let fetchByRange = """
    SELECT date_local, power_kwh, wifi_gb, power_cost_yen, network_cost_yen,
           coverage_ratio_power, coverage_ratio_wifi,
           sample_count_power, sample_count_wifi, computed_at_ms
    FROM daily_rollups
    WHERE date_local >= ? AND date_local <= ?
    ORDER BY date_local ASC
    """

    /// 保持期限を超えた日次ロールアップを削除する
    static let purge = """
    DELETE FROM daily_rollups WHERE date_local < ?
    """

    /// 月次電力料金を合算する (月次リセット日対応)
    static let monthlyPowerCost = """
    SELECT SUM(power_cost_yen) FROM daily_rollups
    WHERE date_local >= ? AND date_local <= ?
    """

    /// 月次 Wi-Fi 累計 GB を合算する (月次リセット日対応)
    static let monthlyWifiGb = """
    SELECT SUM(wifi_gb) AS total_gb FROM daily_rollups
    WHERE date_local >= ? AND date_local <= ?
    """

    /// 月次通信料金を合算する (fixed モデル用)
    static let monthlyNetworkCost = """
    SELECT SUM(network_cost_yen) FROM daily_rollups
    WHERE date_local >= ? AND date_local <= ?
    """

    /// 全ロールアップの日付一覧を取得する (昇順)
    static let fetchAllDates = """
    SELECT date_local FROM daily_rollups ORDER BY date_local ASC
    """

    /// 月次電力量 (kWh) を合算する
    static let monthlyPowerKwh = """
    SELECT SUM(power_kwh) FROM daily_rollups
    WHERE date_local >= ? AND date_local <= ?
    """

    /// サンプルが存在する全日付を取得する (電力 + Wi-Fi の UNION)
    static let fetchAllSampleDates = """
    SELECT DISTINCT day FROM (
        SELECT date(captured_at_ms / 1000, 'unixepoch', 'localtime') AS day FROM power_samples
        UNION
        SELECT date(captured_at_ms / 1000, 'unixepoch', 'localtime') AS day FROM wifi_samples
    ) ORDER BY day ASC
    """
}
