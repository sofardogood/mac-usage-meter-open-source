import Foundation

/// 統合状態コード (第6章)
///
/// M-001〜M-009 を定義。全画面・ログ・エラーハンドリングの唯一の正規定義。
enum StateCode: String, Codable, CaseIterable, Sendable {
    /// M-001: 管理者権限未付与 (fatal, retryable=false, 影響: 電力)
    case authNotGranted = "M-001"

    /// M-002: Helper 未登録/起動不可 (fatal, retryable=true, 影響: 電力+Wi-Fi)
    case helperNotRegistered = "M-002"

    /// M-003: powermetrics 非対応/メトリクス欠測 (degraded, retryable=false, 影響: 電力)
    case powerMetricsUnsupported = "M-003"

    /// M-004: 起動直後の取得待ち (informational, retryable=false, 影響: 電力+Wi-Fi)
    case initialDataPending = "M-004"

    /// M-005: 電力データの取得または解析失敗 (degraded, retryable=true, 影響: 電力)
    case powerDataFailure = "M-005"

    /// M-006: Wi-Fi インターフェース不明 (degraded, retryable=true, 影響: Wi-Fi)
    case wifiInterfaceUnknown = "M-006"

    /// M-007: stale 継続 — 鮮度閾値超過 (degraded, retryable=true, 影響: 電力/Wi-Fi)
    case staleContinued = "M-007"

    /// M-008: DB 障害 — オープン失敗/書込失敗 (fatal, retryable=true, 影響: 保存)
    case databaseFailure = "M-008"

    /// M-009: Wi-Fi 未接続 (informational, retryable=false, 影響: Wi-Fi)
    case wifiDisconnected = "M-009"

    // MARK: - Properties

    /// 重大度
    var severity: Severity {
        switch self {
        case .authNotGranted, .helperNotRegistered, .databaseFailure:
            return .fatal
        case .powerMetricsUnsupported, .powerDataFailure, .wifiInterfaceUnknown, .staleContinued:
            return .degraded
        case .initialDataPending, .wifiDisconnected:
            return .informational
        }
    }

    /// リトライ可能かどうか
    var isRetryable: Bool {
        switch self {
        case .helperNotRegistered, .powerDataFailure, .wifiInterfaceUnknown,
             .staleContinued, .databaseFailure:
            return true
        case .authNotGranted, .powerMetricsUnsupported, .initialDataPending, .wifiDisconnected:
            return false
        }
    }

    /// 影響範囲
    var affectedScope: AffectedScope {
        switch self {
        case .authNotGranted, .powerMetricsUnsupported, .powerDataFailure:
            return .power
        case .wifiInterfaceUnknown, .wifiDisconnected:
            return .wifi
        case .helperNotRegistered, .initialDataPending:
            return .powerAndWifi
        case .staleContinued:
            return .powerOrWifi
        case .databaseFailure:
            return .storage
        }
    }

    /// ユーザー向け文言
    var userMessage: String {
        switch self {
        case .authNotGranted:
            return "Permission required for power measurement has not been granted"
        case .helperNotRegistered:
            return "The measurement helper could not be started"
        case .powerMetricsUnsupported:
            return "Power readings are unavailable in this environment"
        case .initialDataPending:
            return "Fetching the latest data"
        case .powerDataFailure:
            return "Failed to collect or parse power data"
        case .wifiInterfaceUnknown:
            return "The Wi-Fi interface could not be identified"
        case .staleContinued:
            return "Data is stale; displayed values are for reference only"
        case .databaseFailure:
            return "The data storage location is unavailable"
        case .wifiDisconnected:
            return "Wi-Fi is not connected"
        }
    }

    /// 主操作
    var primaryAction: String {
        switch self {
        case .authNotGranted:
            return "Restart setup"
        case .helperNotRegistered:
            return "Retry registration"
        case .powerMetricsUnsupported:
            return "Open help"
        case .initialDataPending:
            return "Waiting for automatic update"
        case .powerDataFailure:
            return "Retry / View diagnostics"
        case .wifiInterfaceUnknown:
            return "Check network status"
        case .staleContinued:
            return "Retry"
        case .databaseFailure:
            return "Check storage / Restart"
        case .wifiDisconnected:
            return "Open network settings"
        }
    }

    /// 優先順位 (1が最高)
    var priority: Int {
        switch self {
        case .databaseFailure:          return 1
        case .authNotGranted:           return 2
        case .helperNotRegistered:      return 2
        case .powerMetricsUnsupported:  return 3
        case .powerDataFailure:         return 3
        case .staleContinued:           return 4
        case .wifiInterfaceUnknown:     return 4
        case .wifiDisconnected:         return 5
        case .initialDataPending:       return 6
        }
    }

    // MARK: - Nested Types

    /// 重大度レベル
    enum Severity: String, Codable, Sendable {
        case fatal
        case degraded
        case informational
    }

    /// 影響範囲
    enum AffectedScope: String, Codable, Sendable {
        case power
        case wifi
        case powerAndWifi
        case powerOrWifi
        case storage
    }
}
