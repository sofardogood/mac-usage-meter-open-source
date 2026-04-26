import Foundation

/// エラーコード完全一覧 (第13章)
///
/// 各エラーについて検知条件、対応する状態コード、リトライ方針を定義する。
enum ErrorCode: String, Codable, CaseIterable, Sendable {

    // MARK: - AUTH系: 権限関連

    /// AUTH-001: 管理者権限取得失敗 → M-001
    case authPrivilegeFailure = "AUTH-001"

    /// AUTH-002: 権限状態確認失敗 (RELOAD_PRIVILEGE_STATE) → M-001
    case authStateCheckFailure = "AUTH-002"

    // MARK: - HELP系: Helper関連

    /// HELP-001: Helper 未登録/起動不可 → M-002
    case helperNotAvailable = "HELP-001"

    // MARK: - PWR系: 電力取得関連

    /// PWR-001: powermetrics 実行不可 → M-005
    case powerMetricsExecFailure = "PWR-001"

    /// PWR-002: powermetrics 非対応/メトリクス欠測 → M-003
    case powerMetricsUnsupported = "PWR-002"

    /// PWR-003: パーサー失敗 → M-005
    case powerParserFailure = "PWR-003"

    /// PWR-004: powermetrics タイムアウト → M-005 → M-007
    case powerTimeout = "PWR-004"

    // MARK: - NET系: ネットワーク関連

    /// NET-001: Wi-Fi インターフェース不明 → M-006
    case netInterfaceUnknown = "NET-001"

    /// NET-002: カウンタ差分負値 → 状態コードなし
    case netCounterReset = "NET-002"

    /// NET-003: Wi-Fi スナップショット失敗 → M-006
    case netSnapshotFailure = "NET-003"

    // MARK: - DB系: データベース関連

    /// DB-001: DB オープン失敗 → M-008
    case dbOpenFailure = "DB-001"

    /// DB-002: 書き込み失敗 → M-008
    case dbWriteFailure = "DB-002"

    /// DB-003: migration 失敗 → M-008
    case dbMigrationFailure = "DB-003"

    // MARK: - IPC系: XPC通信関連

    /// IPC-001: PING 応答なし → M-002
    case ipcPingFailure = "IPC-001"

    /// IPC-002: GET_SERVICE_STATUS 応答なし → M-002
    case ipcServiceStatusFailure = "IPC-002"

    /// IPC-003: GET_CAPABILITIES 応答なし → M-002
    case ipcCapabilitiesFailure = "IPC-003"

    /// IPC-004: REQUEST_POWER_SAMPLE 応答なし → M-005 → M-007
    case ipcPowerSampleFailure = "IPC-004"

    /// IPC-005: REQUEST_WIFI_SNAPSHOT 応答なし → M-006
    case ipcWifiSnapshotFailure = "IPC-005"

    /// IPC-006: COLLECT_HEALTH_REPORT 応答なし → 状態コードなし
    case ipcHealthReportFailure = "IPC-006"

    // MARK: - DBG系: デバッグ関連

    /// DBG-001: ROTATE_DEBUG_CAPTURE 失敗 → 状態コードなし
    case debugRotateFailure = "DBG-001"

    // MARK: - Properties

    /// 対応する状態コード (存在する場合)
    var stateCode: StateCode? {
        switch self {
        case .authPrivilegeFailure, .authStateCheckFailure:
            return .authNotGranted
        case .helperNotAvailable, .ipcPingFailure, .ipcServiceStatusFailure, .ipcCapabilitiesFailure:
            return .helperNotRegistered
        case .powerMetricsUnsupported:
            return .powerMetricsUnsupported
        case .powerMetricsExecFailure, .powerParserFailure, .powerTimeout, .ipcPowerSampleFailure:
            return .powerDataFailure
        case .netInterfaceUnknown, .netSnapshotFailure, .ipcWifiSnapshotFailure:
            return .wifiInterfaceUnknown
        case .dbOpenFailure, .dbWriteFailure, .dbMigrationFailure:
            return .databaseFailure
        case .netCounterReset, .ipcHealthReportFailure, .debugRotateFailure:
            return nil
        }
    }

    /// ユーザー向け文言
    var userMessage: String {
        switch self {
        case .authPrivilegeFailure:
            return "電力計測の権限が未付与です"
        case .authStateCheckFailure:
            return "権限状態を確認できません"
        case .helperNotAvailable:
            return "計測ヘルパーを開始できません"
        case .powerMetricsExecFailure:
            return "電力データの取得または解析に失敗しました"
        case .powerMetricsUnsupported:
            return "この環境では電力値が得られません"
        case .powerParserFailure:
            return "電力データの解析に失敗しました"
        case .powerTimeout:
            return "電力取得がタイムアウトしました"
        case .netInterfaceUnknown:
            return "Wi-Fi インターフェースを特定できません"
        case .netCounterReset:
            return "通信量を一時的に集計できません"
        case .netSnapshotFailure:
            return "通信量取得に失敗しました"
        case .dbOpenFailure:
            return "保存領域にアクセスできません"
        case .dbWriteFailure:
            return "データ保存に失敗しました"
        case .dbMigrationFailure:
            return "データ形式の更新に失敗しました"
        case .ipcPingFailure:
            return "内部通信を確認しています"
        case .ipcServiceStatusFailure:
            return "サービス状態を取得できません"
        case .ipcCapabilitiesFailure:
            return "能力情報を取得できません"
        case .ipcPowerSampleFailure:
            return "内部通信が途切れました"
        case .ipcWifiSnapshotFailure:
            return "Wi-Fi 情報の取得に失敗しました"
        case .ipcHealthReportFailure:
            return "診断情報を取得できません"
        case .debugRotateFailure:
            return "デバッグ設定の変更に失敗しました"
        }
    }

    /// リトライ可能かどうか
    var isRetryable: Bool {
        switch self {
        case .authPrivilegeFailure, .powerMetricsUnsupported, .ipcHealthReportFailure, .debugRotateFailure:
            return false
        default:
            return true
        }
    }
}
