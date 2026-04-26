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
            return "電力計測に必要な権限が未付与です"
        case .helperNotRegistered:
            return "計測ヘルパーを開始できません"
        case .powerMetricsUnsupported:
            return "この環境では電力値を取得できません"
        case .initialDataPending:
            return "最新データを取得中です"
        case .powerDataFailure:
            return "電力データの取得または解析に失敗しました"
        case .wifiInterfaceUnknown:
            return "Wi-Fi インターフェースを特定できません"
        case .staleContinued:
            return "データが古くなっています。表示値は参考値です"
        case .databaseFailure:
            return "保存領域にアクセスできません"
        case .wifiDisconnected:
            return "Wi-Fi が接続されていません"
        }
    }

    /// 主操作
    var primaryAction: String {
        switch self {
        case .authNotGranted:
            return "セットアップを再開"
        case .helperNotRegistered:
            return "登録を再試行"
        case .powerMetricsUnsupported:
            return "ヘルプを開く"
        case .initialDataPending:
            return "自動更新待ち"
        case .powerDataFailure:
            return "再試行 / 診断表示"
        case .wifiInterfaceUnknown:
            return "ネットワーク状態を確認"
        case .staleContinued:
            return "再試行"
        case .databaseFailure:
            return "保存先を確認 / 再起動"
        case .wifiDisconnected:
            return "ネットワーク設定を開く"
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
