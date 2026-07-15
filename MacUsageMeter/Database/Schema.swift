import Foundation

/// DDL 定義 (付録B)
///
/// SQLite スキーマの DDL を文字列定数として保持する。
enum Schema {

    /// 初期スキーマ DDL (user_version 1)
    static let initialDDL = """
    PRAGMA journal_mode=WAL;

    CREATE TABLE power_samples (
      id                  INTEGER PRIMARY KEY AUTOINCREMENT,
      captured_at_ms      INTEGER NOT NULL,
      avg_watts           REAL    NULL,
      sample_duration_sec REAL    NOT NULL,
      source_level        TEXT    NOT NULL CHECK(source_level IN ('A','B','C')),
      status              TEXT    NOT NULL CHECK(status IN ('success','partial','missing','fail','stale')),
      parser_status       TEXT    NOT NULL CHECK(parser_status IN ('success','partial','fail')),
      outlier_flag        INTEGER NOT NULL DEFAULT 0 CHECK(outlier_flag IN (0,1)),
      raw_capture_id      TEXT    NULL,
      error_code          TEXT    NULL
    );
    CREATE INDEX idx_power_captured_at ON power_samples(captured_at_ms);

    CREATE TABLE wifi_samples (
      id                  INTEGER PRIMARY KEY AUTOINCREMENT,
      captured_at_ms      INTEGER NOT NULL,
      interface_name      TEXT    NOT NULL,
      sent_bytes_total    INTEGER NOT NULL,
      recv_bytes_total    INTEGER NOT NULL,
      sent_bytes_delta    INTEGER NOT NULL DEFAULT 0,
      recv_bytes_delta    INTEGER NOT NULL DEFAULT 0,
      counter_reset_flag  INTEGER NOT NULL DEFAULT 0 CHECK(counter_reset_flag IN (0,1)),
      status              TEXT    NOT NULL CHECK(status IN ('success','missing','fail')),
      error_code          TEXT    NULL
    );
    CREATE INDEX idx_wifi_captured_at ON wifi_samples(captured_at_ms);

    CREATE TABLE daily_rollups (
      date_local            TEXT    PRIMARY KEY,
      power_kwh             REAL    NULL,
      wifi_gb               REAL    NULL,
      power_cost_yen        REAL    NULL,
      network_cost_yen      REAL    NULL,
      coverage_ratio_power  REAL    NOT NULL DEFAULT 0 CHECK(coverage_ratio_power >= 0 AND coverage_ratio_power <= 1),
      coverage_ratio_wifi   REAL    NOT NULL DEFAULT 0 CHECK(coverage_ratio_wifi >= 0 AND coverage_ratio_wifi <= 1),
      sample_count_power    INTEGER NOT NULL DEFAULT 0,
      sample_count_wifi     INTEGER NOT NULL DEFAULT 0,
      computed_at_ms        INTEGER NOT NULL
    );

    CREATE TABLE app_settings (
      key            TEXT    PRIMARY KEY,
      value_text     TEXT    NULL,
      value_number   REAL    NULL,
      value_bool     INTEGER NULL,
      updated_at_ms  INTEGER NOT NULL
    );

    CREATE TABLE audit_events (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      occurred_at_ms  INTEGER NOT NULL,
      event_type      TEXT    NOT NULL,
      severity        TEXT    NOT NULL CHECK(severity IN ('debug','info','warn','error')),
      component       TEXT    NOT NULL,
      error_code      TEXT    NULL,
      detail_json     TEXT    NULL
    );
    CREATE INDEX idx_audit_occurred_at ON audit_events(occurred_at_ms);

    CREATE TABLE maintenance_log (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      ran_at_ms    INTEGER NOT NULL,
      job_name     TEXT    NOT NULL,
      result       TEXT    NOT NULL CHECK(result IN ('success','partial','fail')),
      deleted_rows INTEGER NOT NULL DEFAULT 0,
      notes        TEXT    NULL
    );

    CREATE TABLE debug_captures (
      id                TEXT    PRIMARY KEY,
      captured_at_ms    INTEGER NOT NULL,
      command           TEXT    NOT NULL,
      raw_stdout        TEXT    NULL,
      raw_stderr        TEXT    NULL,
      exit_code         INTEGER NULL,
      related_sample_id INTEGER NULL
    );
    CREATE INDEX idx_debug_captured_at ON debug_captures(captured_at_ms);
    """

    /// power_samples テーブル名
    static let powerSamplesTable = "power_samples"

    /// wifi_samples テーブル名
    static let wifiSamplesTable = "wifi_samples"

    /// daily_rollups テーブル名
    static let dailyRollupsTable = "daily_rollups"

    /// app_settings テーブル名
    static let appSettingsTable = "app_settings"

    /// audit_events テーブル名
    static let auditEventsTable = "audit_events"

    /// maintenance_log テーブル名
    static let maintenanceLogTable = "maintenance_log"

    /// debug_captures テーブル名
    static let debugCapturesTable = "debug_captures"

    static let attributedUsageTable = "attributed_usage"
}
