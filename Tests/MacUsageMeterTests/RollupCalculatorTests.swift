import XCTest
@testable import MacUsageMeter

/// ロールアップ計算の単体テスト (第16.1節)
///
/// 観点: power_kwh 変換、coverage_ratio 計算、除外条件 (fail/outlier)
/// 仕様書 9.1〜9.2 に基づく
final class RollupCalculatorTests: XCTestCase {

    var calculator: RollupCalculator!

    override func setUp() {
        super.setUp()
        calculator = RollupCalculator()
    }

    // MARK: - Power kWh (9.1)

    /// power_kwh = Sigma(avg_watts * sample_duration_sec) / 3,600,000
    /// 例: 50W * 60秒 = 3000 Ws → 3000 / 3,600,000 = 0.000833... kWh
    ///     2 サンプル → 0.001667 kWh
    func test_powerKwh_normalSamples_correctCalculation() {
        let samples = [
            makePowerSample(avgWatts: 50.0, durationSec: 60.0, status: .success),
            makePowerSample(avgWatts: 50.0, durationSec: 60.0, status: .success),
        ]

        let kwh = calculator.calculatePowerKwh(from: samples)

        // (50*60 + 50*60) / 3_600_000 = 6000 / 3_600_000 = 0.001667
        XCTAssertEqual(kwh, 0.00167, accuracy: 0.00001)
    }

    /// 1日分のサンプル (1440件 * 60秒間隔 * 42W 平均)
    /// power_kwh = (42 * 60 * 1440) / 3,600,000 = 3,628,800 / 3,600,000 = 1.008 kWh
    func test_powerKwh_fullDay_realisticValue() {
        let samples = (0..<1440).map { _ in
            makePowerSample(avgWatts: 42.0, durationSec: 60.0, status: .success)
        }

        let kwh = calculator.calculatePowerKwh(from: samples)

        XCTAssertEqual(kwh, 1.008, accuracy: 0.001)
    }

    /// status=fail のサンプルは除外
    func test_powerKwh_failSamples_excluded() {
        let samples = [
            makePowerSample(avgWatts: 50.0, durationSec: 60.0, status: .success),
            makePowerSample(avgWatts: 100.0, durationSec: 60.0, status: .fail),
            makePowerSample(avgWatts: 50.0, durationSec: 60.0, status: .success),
        ]

        let kwh = calculator.calculatePowerKwh(from: samples)

        // fail を除外: (50*60 + 50*60) / 3,600,000 = 0.001667
        XCTAssertEqual(kwh, 0.00167, accuracy: 0.00001)
    }

    /// outlier_flag=1 のサンプルは除外
    func test_powerKwh_outlierSamples_excluded() {
        let samples = [
            makePowerSample(avgWatts: 50.0, durationSec: 60.0, status: .success),
            makePowerSample(avgWatts: 700.0, durationSec: 60.0, status: .success, outlierFlag: 1),
            makePowerSample(avgWatts: 50.0, durationSec: 60.0, status: .success),
        ]

        let kwh = calculator.calculatePowerKwh(from: samples)

        // outlier を除外: (50*60 + 50*60) / 3,600,000 = 0.001667
        XCTAssertEqual(kwh, 0.00167, accuracy: 0.00001)
    }

    /// avg_watts が nil のサンプルは除外
    func test_powerKwh_nullWatts_excluded() {
        let samples = [
            makePowerSample(avgWatts: 50.0, durationSec: 60.0, status: .success),
            makePowerSample(avgWatts: nil, durationSec: 60.0, status: .missing),
            makePowerSample(avgWatts: 50.0, durationSec: 60.0, status: .success),
        ]

        let kwh = calculator.calculatePowerKwh(from: samples)

        // nil を除外: (50*60 + 50*60) / 3,600,000 = 0.001667
        XCTAssertEqual(kwh, 0.00167, accuracy: 0.00001)
    }

    /// status=partial + avg_watts 非 nil → 含める
    func test_powerKwh_partialWithValue_included() {
        let samples = [
            makePowerSample(avgWatts: 50.0, durationSec: 60.0, status: .success),
            makePowerSample(avgWatts: 40.0, durationSec: 60.0, status: .partial),
            makePowerSample(avgWatts: 50.0, durationSec: 60.0, status: .success),
        ]

        let kwh = calculator.calculatePowerKwh(from: samples)

        // partial を含む: (50*60 + 40*60 + 50*60) / 3,600,000 = 8400 / 3,600,000 = 0.002333
        XCTAssertEqual(kwh, 0.00233, accuracy: 0.00001)
    }

    /// status=stale → 含める
    func test_powerKwh_staleSamples_included() {
        let samples = [
            makePowerSample(avgWatts: 50.0, durationSec: 60.0, status: .success),
            makePowerSample(avgWatts: 45.0, durationSec: 60.0, status: .stale),
        ]

        let kwh = calculator.calculatePowerKwh(from: samples)

        // stale を含む: (50*60 + 45*60) / 3,600,000 = 5700 / 3,600,000 = 0.001583
        XCTAssertEqual(kwh, 0.00158, accuracy: 0.00001)
    }

    /// 小数第6位で四捨五入
    func test_powerKwh_rounding_roundedToFiveDecimalPlaces() {
        // 33W * 60sec = 1980 Ws / 3,600,000 = 0.00055 kWh (ちょうど5桁)
        let samples = [
            makePowerSample(avgWatts: 33.0, durationSec: 60.0, status: .success),
        ]

        let kwh = calculator.calculatePowerKwh(from: samples)

        XCTAssertEqual(kwh, 0.00055, accuracy: 0.000001)
    }

    /// サンプル 0 件 → 0.0 kWh
    func test_powerKwh_noSamples_zeroKwh() {
        let kwh = calculator.calculatePowerKwh(from: [])
        XCTAssertEqual(kwh, 0.0, accuracy: 0.000001)
    }

    // MARK: - Wi-Fi GB (8.3)

    /// wifi_gb = Sigma(sent_bytes_delta + recv_bytes_delta) / 10^9
    func test_wifiGb_normalSamples_correctCalculation() {
        let samples = [
            makeWifiSample(sentDelta: 100_000_000, recvDelta: 400_000_000),  // 500 MB
            makeWifiSample(sentDelta: 200_000_000, recvDelta: 300_000_000),  // 500 MB
        ]

        let gb = calculator.calculateWifiGb(from: samples)

        // (500_000_000 + 500_000_000) / 1_000_000_000 = 1.0 GB
        XCTAssertEqual(gb, 1.0, accuracy: 0.001)
    }

    /// 小数第4位で四捨五入
    func test_wifiGb_rounding_roundedToThreeDecimalPlaces() {
        let samples = [
            makeWifiSample(sentDelta: 123_456_789, recvDelta: 0),
        ]

        let gb = calculator.calculateWifiGb(from: samples)

        // 123_456_789 / 1_000_000_000 = 0.123456789 → 小数第4位で四捨五入 → 0.123
        XCTAssertEqual(gb, 0.123, accuracy: 0.001)
    }

    /// サンプル 0 件 → 0.0 GB
    func test_wifiGb_noSamples_zeroGb() {
        let gb = calculator.calculateWifiGb(from: [])
        XCTAssertEqual(gb, 0.0, accuracy: 0.001)
    }

    // MARK: - Coverage Ratio (9.2)

    /// coverage_ratio = 有効サンプル数 / floor(86400 / interval)
    /// 60秒間隔: 1440 期待サンプル、1440 有効 → 1.0
    func test_coverageRatio_fullDay_onePointZero() {
        let ratio = calculator.calculateCoverageRatio(
            validSampleCount: 1440,
            targetSeconds: 86400,
            samplingIntervalSec: 60
        )
        XCTAssertEqual(ratio, 1.0, accuracy: 0.001)
    }

    /// 半分のサンプル → 0.5
    func test_coverageRatio_halfDay_zeroPointFive() {
        let ratio = calculator.calculateCoverageRatio(
            validSampleCount: 720,
            targetSeconds: 86400,
            samplingIntervalSec: 60
        )
        XCTAssertEqual(ratio, 0.5, accuracy: 0.001)
    }

    /// 1.0 を超える場合は 1.0 に切り詰め
    func test_coverageRatio_exceedsOne_clampedToOne() {
        let ratio = calculator.calculateCoverageRatio(
            validSampleCount: 2000,
            targetSeconds: 86400,
            samplingIntervalSec: 60
        )
        XCTAssertEqual(ratio, 1.0, accuracy: 0.001)
    }

    /// 当日の coverage_ratio (経過秒数ベース)
    /// 3600秒経過、60秒間隔 → 期待60件、30件有効 → 0.5
    func test_coverageRatio_currentDay_elapsedSecondsBased() {
        let ratio = calculator.calculateCoverageRatio(
            validSampleCount: 30,
            targetSeconds: 3600,
            samplingIntervalSec: 60
        )
        XCTAssertEqual(ratio, 0.5, accuracy: 0.001)
    }

    /// サンプル 0 件 → coverage_ratio = 0
    func test_coverageRatio_zeroSamples_zero() {
        let ratio = calculator.calculateCoverageRatio(
            validSampleCount: 0,
            targetSeconds: 86400,
            samplingIntervalSec: 60
        )
        XCTAssertEqual(ratio, 0.0, accuracy: 0.001)
    }

    /// 小数第4位で四捨五入 (3桁保持)
    func test_coverageRatio_rounding_threeDecimalPlaces() {
        // 1000 / 1440 = 0.694444... → 0.694
        let ratio = calculator.calculateCoverageRatio(
            validSampleCount: 1000,
            targetSeconds: 86400,
            samplingIntervalSec: 60
        )
        XCTAssertEqual(ratio, 0.694, accuracy: 0.001)
    }

    // MARK: - Test Helpers

    private func makePowerSample(
        avgWatts: Double?,
        durationSec: Double,
        status: PowerSample.SampleStatus,
        outlierFlag: Int = 0
    ) -> PowerSample {
        PowerSample(
            id: nil,
            capturedAtMs: Int64(Date().timeIntervalSince1970 * 1000),
            avgWatts: avgWatts,
            sampleDurationSec: durationSec,
            sourceLevel: .a,
            status: status,
            parserStatus: .success,
            outlierFlag: outlierFlag,
            rawCaptureId: nil,
            errorCode: nil
        )
    }

    private func makeWifiSample(sentDelta: Int64, recvDelta: Int64) -> WifiSample {
        WifiSample(
            id: nil,
            capturedAtMs: Int64(Date().timeIntervalSince1970 * 1000),
            interfaceName: "en0",
            sentBytesTotal: sentDelta,
            recvBytesTotal: recvDelta,
            sentBytesDelta: sentDelta,
            recvBytesDelta: recvDelta,
            counterResetFlag: 0,
            status: .success,
            errorCode: nil
        )
    }
}
