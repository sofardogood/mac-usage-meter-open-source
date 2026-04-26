import Foundation

/// Wi-Fi サンプル (wifi_samples テーブル対応)
///
/// getifaddrs() + if_data から取得した Wi-Fi カウンタのスナップショット。
/// 差分計算は Collector Controller 側で行う。
struct WifiSample: Codable, Sendable, Identifiable {
    /// PRIMARY KEY AUTOINCREMENT
    let id: Int64?

    /// 採取時刻 (UTC Epoch ms)
    let capturedAtMs: Int64

    /// Wi-Fi インターフェース名 (例: en0)
    let interfaceName: String

    /// 送信バイト数 (累積カウンタ値)
    let sentBytesTotal: Int64

    /// 受信バイト数 (累積カウンタ値)
    let recvBytesTotal: Int64

    /// 送信バイト差分 (前回との差分)
    let sentBytesDelta: Int64

    /// 受信バイト差分 (前回との差分)
    let recvBytesDelta: Int64

    /// カウンタリセットフラグ (0 or 1)
    /// 差分が負値の場合に 1 を設定
    let counterResetFlag: Int

    /// ステータス
    let status: WifiSampleStatus

    /// エラーコード
    let errorCode: String?

    // MARK: - Nested Types

    /// Wi-Fi サンプルステータス
    enum WifiSampleStatus: String, Codable, Sendable {
        case success
        case missing
        case fail
    }
}
