import Foundation

/// 監査イベント (audit_events テーブル対応)
///
/// 権限操作、失敗、設定変更、保守実行時に記録する。
/// PII を含めず構造化ログで保存する。
struct AuditEvent: Codable, Sendable, Identifiable {
    /// PRIMARY KEY AUTOINCREMENT
    let id: Int64?

    /// 発生時刻 (UTC Epoch ms)
    let occurredAtMs: Int64

    /// イベント種別
    let eventType: EventType

    /// 重大度
    let severity: Severity

    /// コンポーネント名
    let component: String

    /// エラーコード (任意)
    let errorCode: String?

    /// 詳細 JSON (任意)
    let detailJson: String?

    // MARK: - Nested Types

    /// イベント種別 (10.6.2節)
    enum EventType: String, Codable, Sendable {
        case helperRegistered = "helper_registered"
        case helperUnregistered = "helper_unregistered"
        case helperRegisterFailed = "helper_register_failed"
        case privilegeGranted = "privilege_granted"
        case privilegeDenied = "privilege_denied"
        case settingChanged = "setting_changed"
        case powerSampleFailed = "power_sample_failed"
        case wifiSampleFailed = "wifi_sample_failed"
        case parserFailed = "parser_failed"
        case rollupCompleted = "rollup_completed"
        case purgeCompleted = "purge_completed"
        case migrationCompleted = "migration_completed"
        case migrationFailed = "migration_failed"
        case dbWriteFailed = "db_write_failed"
        case stateTransition = "state_transition"
        case helperCrashDetected = "helper_crash_detected"
        case vacuumCompleted = "vacuum_completed"
        case debugCaptureToggled = "debug_capture_toggled"
    }

    /// 重大度
    enum Severity: String, Codable, Sendable {
        case debug
        case info
        case warn
        case error
    }
}

/// 監査イベント detail_json の構造 (10.6.1節)
struct AuditEventDetail: Codable, Sendable {
    /// 内部エラーコード (例: AUTH-001, PWR-003)
    var errorCode: String?

    /// 状態コード (例: M-001, M-005)
    var stateCode: String?

    /// 変更前の値
    var previousValue: AnyCodableValue?

    /// 変更後の値
    var newValue: AnyCodableValue?

    /// 補足情報 (例: 対象設定キー名、インターフェース名)
    var context: String?

    /// 処理にかかった時間 (ミリ秒)
    var durationMs: Int?
}

/// JSON で任意の型を保持するための Codable ラッパー
enum AnyCodableValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.typeMismatch(
                AnyCodableValue.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported type")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        }
    }
}
