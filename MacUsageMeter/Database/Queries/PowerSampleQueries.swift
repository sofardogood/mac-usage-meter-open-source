import Foundation

/// 電力サンプル関連の SQL クエリ定義
enum PowerSampleQueries {

    /// 電力サンプルを挿入する
    static let insert = """
    INSERT INTO power_samples (
        captured_at_ms, avg_watts, sample_duration_sec, source_level,
        status, parser_status, outlier_flag, raw_capture_id, error_code
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    """

    /// 指定期間の電力サンプルを取得する (captured_at_ms 昇順)
    static let fetchByRange = """
    SELECT id, captured_at_ms, avg_watts, sample_duration_sec, source_level,
           status, parser_status, outlier_flag, raw_capture_id, error_code
    FROM power_samples
    WHERE captured_at_ms >= ? AND captured_at_ms <= ?
    ORDER BY captured_at_ms ASC
    """

    /// 最新の電力サンプルを1件取得する
    static let fetchLatest = """
    SELECT id, captured_at_ms, avg_watts, sample_duration_sec, source_level,
           status, parser_status, outlier_flag, raw_capture_id, error_code
    FROM power_samples
    ORDER BY captured_at_ms DESC
    LIMIT 1
    """

    /// 最新の成功した電力サンプルを1件取得する (avg_watts が NOT NULL)
    static let fetchLatestSuccess = """
    SELECT id, captured_at_ms, avg_watts, sample_duration_sec, source_level,
           status, parser_status, outlier_flag, raw_capture_id, error_code
    FROM power_samples
    WHERE avg_watts IS NOT NULL AND status IN ('success', 'partial')
    ORDER BY captured_at_ms DESC
    LIMIT 1
    """

    /// 保持期限を超えた電力サンプルを削除する
    static let purge = """
    DELETE FROM power_samples WHERE captured_at_ms < ?
    """

    /// 指定期間の電力量合計 (Watt-seconds) を算出する
    static let sumWattSeconds = """
    SELECT COALESCE(SUM(avg_watts * sample_duration_sec), 0)
    FROM power_samples
    WHERE captured_at_ms >= ? AND captured_at_ms <= ?
      AND status IN ('success', 'partial')
      AND outlier_flag = 0
      AND avg_watts IS NOT NULL
    """

    /// 直近1時間の平均電力を算出する (status=success or partial, outlier_flag=0)
    static let recentAverageWatts = """
    SELECT AVG(avg_watts)
    FROM power_samples
    WHERE captured_at_ms >= ?
      AND status IN ('success', 'partial')
      AND outlier_flag = 0
      AND avg_watts IS NOT NULL
    """
}
