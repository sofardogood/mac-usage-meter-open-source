import Foundation

/// Wi-Fi サンプル関連の SQL クエリ定義
enum WifiSampleQueries {

    /// Wi-Fi サンプルを挿入する
    static let insert = """
    INSERT INTO wifi_samples (
        captured_at_ms, interface_name, sent_bytes_total, recv_bytes_total,
        sent_bytes_delta, recv_bytes_delta, counter_reset_flag, status, error_code
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    """

    /// 指定期間の Wi-Fi サンプルを取得する (captured_at_ms 昇順)
    static let fetchByRange = """
    SELECT id, captured_at_ms, interface_name, sent_bytes_total, recv_bytes_total,
           sent_bytes_delta, recv_bytes_delta, counter_reset_flag, status, error_code
    FROM wifi_samples
    WHERE captured_at_ms >= ? AND captured_at_ms <= ?
    ORDER BY captured_at_ms ASC
    """

    /// 最新の Wi-Fi サンプルを1件取得する
    static let fetchLatest = """
    SELECT id, captured_at_ms, interface_name, sent_bytes_total, recv_bytes_total,
           sent_bytes_delta, recv_bytes_delta, counter_reset_flag, status, error_code
    FROM wifi_samples
    ORDER BY captured_at_ms DESC
    LIMIT 1
    """

    /// 保持期限を超えた Wi-Fi サンプルを削除する
    static let purge = """
    DELETE FROM wifi_samples WHERE captured_at_ms < ?
    """

    /// 当日の Wi-Fi 使用量合計を算出する (bytes)
    static let dailyTotalBytes = """
    SELECT COALESCE(SUM(sent_bytes_delta + recv_bytes_delta), 0)
    FROM wifi_samples
    WHERE captured_at_ms >= ? AND captured_at_ms <= ?
      AND status = 'success'
    """
}
