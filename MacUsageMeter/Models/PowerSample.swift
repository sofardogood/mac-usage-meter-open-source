import Foundation

/// 電力サンプル (power_samples テーブル対応)
///
/// powermetrics から取得した単一サンプルを表す。
/// Helper が返した値を Collector Controller が正規化して保存する。
struct PowerSample: Codable, Sendable, Identifiable {
    /// PRIMARY KEY AUTOINCREMENT
    let id: Int64?

    /// 採取時刻 (UTC Epoch ms)
    let capturedAtMs: Int64

    /// 平均電力 (W)。欠測時は nil
    let avgWatts: Double?

    /// サンプル計測時間 (秒)
    let sampleDurationSec: Double

    /// ソースレベル (A/B/C)
    let sourceLevel: SourceLevel

    /// ステータス
    let status: SampleStatus

    /// パーサーステータス
    let parserStatus: ParserStatus

    /// 外れ値フラグ (0 or 1)。600W 超で 1
    let outlierFlag: Int

    /// デバッグキャプチャ ID (debug_captures.id)
    let rawCaptureId: String?

    /// エラーコード
    let errorCode: String?

    // MARK: - Nested Types

    /// ソースレベル
    ///
    /// - A: combined_power or package_power が取得可能 (高精度)
    /// - B: cpu_power のみ取得可能 (部分精度)
    /// - C: いずれも取得不可 (欠測)
    enum SourceLevel: String, Codable, Sendable {
        case a = "A"
        case b = "B"
        case c = "C"
    }

    /// サンプルステータス
    enum SampleStatus: String, Codable, Sendable {
        case success
        case partial
        case missing
        case fail
        case stale
    }

    /// パーサーステータス
    enum ParserStatus: String, Codable, Sendable {
        case success
        case partial
        case fail
    }
}
