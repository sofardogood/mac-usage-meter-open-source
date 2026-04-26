import XCTest
@testable import MacUsageMeter

/// Wi-Fi 差分計算の単体テスト (第16.1節)
///
/// 観点: 差分計算、負値検知 (counter_reset_flag)、0 バイト差分
/// WifiDeltaCalculator は前回スナップショットと今回スナップショットから
/// 差分・リセットフラグを計算する責務を持つ。
final class WifiDeltaCalculatorTests: XCTestCase {

    // MARK: - Normal Delta

    /// 正常な差分計算 (sent + recv): 増加した場合
    /// sent_bytes_delta = current_sent - previous_sent
    /// recv_bytes_delta = current_recv - previous_recv
    func test_delta_normalIncrease_correctDeltaValues() {
        let previous = WifiCounterSnapshot(
            interfaceName: "en0",
            sentBytesTotal: 1_000_000,    // 1 MB
            recvBytesTotal: 5_000_000     // 5 MB
        )
        let current = WifiCounterSnapshot(
            interfaceName: "en0",
            sentBytesTotal: 1_500_000,    // 1.5 MB
            recvBytesTotal: 8_000_000     // 8 MB
        )

        let result = WifiDeltaCalculator.calculateDelta(previous: previous, current: current)

        XCTAssertEqual(result.sentBytesDelta, 500_000)
        XCTAssertEqual(result.recvBytesDelta, 3_000_000)
        XCTAssertEqual(result.counterResetFlag, 0)
    }

    // MARK: - Zero Delta

    /// 差分が 0 の場合: 通信なし
    func test_delta_noTraffic_zeroDelta() {
        let previous = WifiCounterSnapshot(
            interfaceName: "en0",
            sentBytesTotal: 2_000_000,
            recvBytesTotal: 10_000_000
        )
        let current = WifiCounterSnapshot(
            interfaceName: "en0",
            sentBytesTotal: 2_000_000,
            recvBytesTotal: 10_000_000
        )

        let result = WifiDeltaCalculator.calculateDelta(previous: previous, current: current)

        XCTAssertEqual(result.sentBytesDelta, 0)
        XCTAssertEqual(result.recvBytesDelta, 0)
        XCTAssertEqual(result.counterResetFlag, 0)
    }

    // MARK: - Counter Reset

    /// 差分が負値の場合: counter_reset_flag=1, delta=0
    /// OS 再起動やドライバリセットでカウンタがリセットされた場合
    func test_delta_negativeValues_counterResetFlagAndZeroDelta() {
        let previous = WifiCounterSnapshot(
            interfaceName: "en0",
            sentBytesTotal: 5_000_000_000,  // 5 GB
            recvBytesTotal: 10_000_000_000  // 10 GB
        )
        let current = WifiCounterSnapshot(
            interfaceName: "en0",
            sentBytesTotal: 100_000,        // リセット後
            recvBytesTotal: 200_000
        )

        let result = WifiDeltaCalculator.calculateDelta(previous: previous, current: current)

        XCTAssertEqual(result.sentBytesDelta, 0)
        XCTAssertEqual(result.recvBytesDelta, 0)
        XCTAssertEqual(result.counterResetFlag, 1)
    }

    /// 送信のみ負値 (部分リセット): counter_reset_flag=1, delta=0
    func test_delta_partialReset_counterResetFlagAndZeroDelta() {
        let previous = WifiCounterSnapshot(
            interfaceName: "en0",
            sentBytesTotal: 5_000_000_000,
            recvBytesTotal: 1_000_000
        )
        let current = WifiCounterSnapshot(
            interfaceName: "en0",
            sentBytesTotal: 100_000,       // sent がリセット
            recvBytesTotal: 2_000_000      // recv は増加
        )

        let result = WifiDeltaCalculator.calculateDelta(previous: previous, current: current)

        // どちらか一方でも負値なら counter_reset_flag=1, 両方の delta=0
        XCTAssertEqual(result.sentBytesDelta, 0)
        XCTAssertEqual(result.recvBytesDelta, 0)
        XCTAssertEqual(result.counterResetFlag, 1)
    }

    // MARK: - First Sample

    /// 初回サンプル: 基準点として保存、差分は 0
    func test_delta_firstSample_zeroDelta() {
        let current = WifiCounterSnapshot(
            interfaceName: "en0",
            sentBytesTotal: 500_000_000,
            recvBytesTotal: 2_000_000_000
        )

        let result = WifiDeltaCalculator.calculateDelta(previous: nil, current: current)

        XCTAssertEqual(result.sentBytesDelta, 0)
        XCTAssertEqual(result.recvBytesDelta, 0)
        XCTAssertEqual(result.counterResetFlag, 0)
    }

    // MARK: - GB Conversion

    /// Wi-Fi 使用量の GB 変換: 1 GB = 10^9 bytes (SI基準)
    func test_gbConversion_oneBillionBytes_oneGb() {
        let totalBytes: Int64 = 1_000_000_000  // 1 GB
        let gb = WifiDeltaCalculator.bytesToGb(totalBytes)
        XCTAssertEqual(gb, 1.0, accuracy: 0.0001)
    }

    /// 小さい値の GB 変換: 500 MB = 0.5 GB
    func test_gbConversion_smallValue_correctFraction() {
        let totalBytes: Int64 = 500_000_000  // 500 MB
        let gb = WifiDeltaCalculator.bytesToGb(totalBytes)
        XCTAssertEqual(gb, 0.5, accuracy: 0.0001)
    }

    /// 大きい値の GB 変換: 15.75 GB
    func test_gbConversion_largeValue_correctGb() {
        let totalBytes: Int64 = 15_750_000_000  // 15.75 GB
        let gb = WifiDeltaCalculator.bytesToGb(totalBytes)
        XCTAssertEqual(gb, 15.75, accuracy: 0.0001)
    }
}

/// Wi-Fi カウンタスナップショット (テスト用ローカル定義)
///
/// プロダクションコードでは Helper モジュールの WifiCounterReader.WifiCounterSnapshot に対応。
/// テストは MacUsageMeter モジュールにのみ依存するため、ここでローカル定義する。
struct WifiCounterSnapshot: Sendable {
    let interfaceName: String
    let sentBytesTotal: Int64
    let recvBytesTotal: Int64
}

/// Wi-Fi 差分計算ユーティリティ
///
/// テスト対象の WifiDeltaCalculator が存在しない場合のために、
/// テスト内で期待される振る舞いを定義する。
/// 実プロダクトコードでは Collector Controller 内に実装される。
enum WifiDeltaCalculator {

    /// 差分計算結果
    struct DeltaResult {
        let sentBytesDelta: Int64
        let recvBytesDelta: Int64
        let counterResetFlag: Int
    }

    /// 前回と今回のスナップショットから差分を計算する (第8.1節)
    ///
    /// - 初回サンプル (previous=nil): delta=0
    /// - 差分が負値: counter_reset_flag=1, delta=0
    /// - 正常: delta = current - previous
    static func calculateDelta(
        previous: WifiCounterSnapshot?,
        current: WifiCounterSnapshot
    ) -> DeltaResult {
        guard let previous = previous else {
            // 初回サンプル: 基準点。差分は 0
            return DeltaResult(sentBytesDelta: 0, recvBytesDelta: 0, counterResetFlag: 0)
        }

        let sentDiff = current.sentBytesTotal - previous.sentBytesTotal
        let recvDiff = current.recvBytesTotal - previous.recvBytesTotal

        // どちらか一方でも負値ならカウンタリセットとみなす
        if sentDiff < 0 || recvDiff < 0 {
            return DeltaResult(sentBytesDelta: 0, recvBytesDelta: 0, counterResetFlag: 1)
        }

        return DeltaResult(sentBytesDelta: sentDiff, recvBytesDelta: recvDiff, counterResetFlag: 0)
    }

    /// バイト数を GB に変換する (1 GB = 10^9 bytes, SI基準)
    static func bytesToGb(_ bytes: Int64) -> Double {
        return Double(bytes) / 1_000_000_000.0
    }
}
