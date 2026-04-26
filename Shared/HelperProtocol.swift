import Foundation

/// Helper XPC プロトコル (第11.1節)
///
/// UI App (Collector Controller) と Privileged Helper 間の通信プロトコル。
/// Data パラメータは JSONEncoder / JSONDecoder で Codable 構造体をシリアライズ/デシリアライズする。
@objc public protocol HelperProtocol {
    /// 疎通確認 (PING)
    /// タイムアウト: 1秒、リトライ: 0回
    func ping(withReply reply: @escaping (Bool) -> Void)

    /// 登録状態・権限状態・最終エラー取得 (GET_SERVICE_STATUS)
    /// タイムアウト: 2秒、リトライ: 1回
    func getServiceStatus(withReply reply: @escaping (Data) -> Void)

    /// 対応機種・利用可能プロファイル取得 (GET_CAPABILITIES)
    /// タイムアウト: 3秒、リトライ: 1回
    func getCapabilities(withReply reply: @escaping (Data) -> Void)

    /// 単発電力サンプル取得 (REQUEST_POWER_SAMPLE)
    /// タイムアウト: 10秒 (powermetrics 8秒 + IPC マージン 2秒)、リトライ: 1回
    func requestPowerSample(profileId: String, timeoutSec: Int, collectDebugRaw: Bool, withReply reply: @escaping (Data) -> Void)

    /// 単発 Wi-Fi カウンタ取得 (REQUEST_WIFI_SNAPSHOT)
    /// タイムアウト: 3秒、リトライ: 1回
    func requestWifiSnapshot(withReply reply: @escaping (Data) -> Void)

    /// 権限状態の再確認 (RELOAD_PRIVILEGE_STATE)
    /// タイムアウト: 2秒、リトライ: 0回
    func reloadPrivilegeState(withReply reply: @escaping (Data) -> Void)

    /// Helper の診断情報取得 (COLLECT_HEALTH_REPORT)
    /// タイムアウト: 3秒、リトライ: 0回
    func collectHealthReport(withReply reply: @escaping (Data) -> Void)

    /// デバッグ採取の保存切替 (ROTATE_DEBUG_CAPTURE)
    /// タイムアウト: 2秒、リトライ: 0回
    func rotateDebugCapture(enabled: Bool, withReply reply: @escaping (Data) -> Void)
}
