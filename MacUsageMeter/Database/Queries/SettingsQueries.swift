import Foundation

/// 設定関連の SQL クエリ定義
enum SettingsQueries {

    /// 設定を挿入または更新する
    static let upsert = """
    INSERT OR REPLACE INTO app_settings (
        key, value_text, value_number, value_bool, updated_at_ms
    ) VALUES (?, ?, ?, ?, ?)
    """

    /// キーで設定を取得する
    static let fetchByKey = """
    SELECT key, value_text, value_number, value_bool, updated_at_ms
    FROM app_settings
    WHERE key = ?
    """

    /// 全設定を取得する
    static let fetchAll = """
    SELECT key, value_text, value_number, value_bool, updated_at_ms
    FROM app_settings
    ORDER BY key ASC
    """
}

/// 監査イベント関連の SQL クエリ定義
enum AuditEventQueries {

    /// 監査イベントを挿入する
    static let insert = """
    INSERT INTO audit_events (
        occurred_at_ms, event_type, severity, component, error_code, detail_json
    ) VALUES (?, ?, ?, ?, ?, ?)
    """

    /// 保持期限を超えた監査イベントを削除する (error は365日保持)
    static let purge = """
    DELETE FROM audit_events
    WHERE (severity != 'error' AND occurred_at_ms < ?)
       OR (severity = 'error' AND occurred_at_ms < ?)
    """
}

/// メンテナンスログ関連の SQL クエリ定義
enum MaintenanceLogQueries {

    /// メンテナンスログを挿入する
    static let insert = """
    INSERT INTO maintenance_log (
        ran_at_ms, job_name, result, deleted_rows, notes
    ) VALUES (?, ?, ?, ?, ?)
    """

    /// 最新のメンテナンスログを取得する (ジョブ名指定)
    static let fetchLatestByJob = """
    SELECT id, ran_at_ms, job_name, result, deleted_rows, notes
    FROM maintenance_log
    WHERE job_name = ?
    ORDER BY ran_at_ms DESC
    LIMIT 1
    """
}

/// デバッグキャプチャ関連の SQL クエリ定義
enum DebugCaptureQueries {

    /// デバッグキャプチャを挿入する
    static let insert = """
    INSERT INTO debug_captures (
        id, captured_at_ms, command, raw_stdout, raw_stderr, exit_code, related_sample_id
    ) VALUES (?, ?, ?, ?, ?, ?, ?)
    """

    /// 保持期限 (7日) を超えたデバッグキャプチャを削除する
    static let purge = """
    DELETE FROM debug_captures WHERE captured_at_ms < ?
    """
}
