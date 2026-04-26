import XCTest
@testable import MacUsageMeter

/// PowerKwhCalculator の単体テスト (第16.1節)
///
/// 観点: kWh 計算、外れ値判定 (PWR-Q2)、品質チェック (PWR-Q1〜Q3)、集計対象判定
/// 仕様書 9.1, 7.6 に基づく
final class PowerKwhCalculatorTests: XCTestCase {

    var calculator: PowerKwhCalculator!

    override func setUp() {
        super.setUp()
        calculator = PowerKwhCalculator()
    }

    // MARK: - kWh Calculation (9.1)

    /// 基本計算: 50W * 60秒 * 2サンプル / 3,600,000 = 0.00167 kWh
    func test_calculate_normalSamples_correctKwh() {
        let samples = [
            makeSample(avgWatts: 50.0, durationSec: 60.0, status: .success),
            makeSample(avgWatts: 50.0, durationSec: 60.0, status: .success),
        ]
        let kwh = calculator.calculate(from: samples)
        XCTAssertEqual(kwh, 0.00167, accuracy: 0.00001)
    }

    /// 1日分: 42W * 60秒 * 1440サンプル = 1.008 kWh
    func test_calculate_fullDay_realisticValue() {
        let samples = (0..<1440).map { _ in
            makeSample(avgWatts: 42.0, durationSec: 60.0, status: .success)
        }
        let kwh = calculator.calculate(from: samples)
        XCTAssertEqual(kwh, 1.008, accuracy: 0.001)
    }

    /// 空配列 → 0.0 kWh
    func test_calculate_emptySamples_zero() {
        let kwh = calculator.calculate(from: [])
        XCTAssertEqual(kwh, 0.0, accuracy: 0.000001)
    }

    /// fail サンプルは除外
    func test_calculate_failSamples_excluded() {
        let samples = [
            makeSample(avgWatts: 50.0, durationSec: 60.0, status: .success),
            makeSample(avgWatts: 100.0, durationSec: 60.0, status: .fail),
        ]
        let kwh = calculator.calculate(from: samples)
        // fail を除外: 50*60 / 3,600,000 = 0.00083
        XCTAssertEqual(kwh, 0.00083, accuracy: 0.00001)
    }

    /// outlier_flag=1 サンプルは除外
    func test_calculate_outlierSamples_excluded() {
        let samples = [
            makeSample(avgWatts: 50.0, durationSec: 60.0, status: .success),
            makeSample(avgWatts: 700.0, durationSec: 60.0, status: .success, outlierFlag: 1),
        ]
        let kwh = calculator.calculate(from: samples)
        XCTAssertEqual(kwh, 0.00083, accuracy: 0.00001)
    }

    /// avg_watts=nil サンプルは除外
    func test_calculate_nilWatts_excluded() {
        let samples = [
            makeSample(avgWatts: 50.0, durationSec: 60.0, status: .success),
            makeSample(avgWatts: nil, durationSec: 60.0, status: .missing),
        ]
        let kwh = calculator.calculate(from: samples)
        XCTAssertEqual(kwh, 0.00083, accuracy: 0.00001)
    }

    /// partial + avg_watts 非 nil → 含める
    func test_calculate_partialWithValue_included() {
        let samples = [
            makeSample(avgWatts: 50.0, durationSec: 60.0, status: .partial),
        ]
        let kwh = calculator.calculate(from: samples)
        XCTAssertEqual(kwh, 0.00083, accuracy: 0.00001)
    }

    /// stale → 含める
    func test_calculate_staleSamples_included() {
        let samples = [
            makeSample(avgWatts: 50.0, durationSec: 60.0, status: .stale),
        ]
        let kwh = calculator.calculate(from: samples)
        XCTAssertEqual(kwh, 0.00083, accuracy: 0.00001)
    }

    // MARK: - Outlier Detection (PWR-Q2)

    /// 600W 以下は正常
    func test_isOutlier_600W_notOutlier() {
        XCTAssertFalse(calculator.isOutlier(600.0))
    }

    /// 600.01W は外れ値
    func test_isOutlier_above600W_outlier() {
        XCTAssertTrue(calculator.isOutlier(600.01))
    }

    /// 0W は正常
    func test_isOutlier_zeroW_notOutlier() {
        XCTAssertFalse(calculator.isOutlier(0.0))
    }

    /// 外れ値閾値定数が 600.0W であること
    func test_outlierThreshold_is600() {
        XCTAssertEqual(PowerKwhCalculator.outlierThresholdWatts, 600.0)
    }

    // MARK: - Aggregation Validity

    /// success + avg_watts + outlier=0 → 有効
    func test_isValid_successNormalSample_true() {
        let sample = makeSample(avgWatts: 50.0, durationSec: 60.0, status: .success)
        XCTAssertTrue(calculator.isValidForAggregation(sample))
    }

    /// fail → 無効
    func test_isValid_failSample_false() {
        let sample = makeSample(avgWatts: 50.0, durationSec: 60.0, status: .fail)
        XCTAssertFalse(calculator.isValidForAggregation(sample))
    }

    /// outlier_flag=1 → 無効
    func test_isValid_outlierSample_false() {
        let sample = makeSample(avgWatts: 50.0, durationSec: 60.0, status: .success, outlierFlag: 1)
        XCTAssertFalse(calculator.isValidForAggregation(sample))
    }

    /// avg_watts=nil → 無効
    func test_isValid_nilWatts_false() {
        let sample = makeSample(avgWatts: nil, durationSec: 60.0, status: .missing)
        XCTAssertFalse(calculator.isValidForAggregation(sample))
    }

    /// partial + avg_watts 非 nil → 有効
    func test_isValid_partialWithValue_true() {
        let sample = makeSample(avgWatts: 40.0, durationSec: 60.0, status: .partial)
        XCTAssertTrue(calculator.isValidForAggregation(sample))
    }

    /// stale + avg_watts 非 nil → 有効
    func test_isValid_staleWithValue_true() {
        let sample = makeSample(avgWatts: 45.0, durationSec: 60.0, status: .stale)
        XCTAssertTrue(calculator.isValidForAggregation(sample))
    }

    // MARK: - Quality Check (7.6)

    /// PWR-Q1: 負値 → isValid=false, shouldDisplay=false
    func test_qualityCheck_negativeWatts_invalid() {
        let sample = makeSample(avgWatts: -5.0, durationSec: 60.0, status: .success)
        let result = calculator.qualityCheck(sample)
        XCTAssertFalse(result.isValid)
        XCTAssertFalse(result.isOutlier)
        XCTAssertFalse(result.shouldDisplay)
    }

    /// PWR-Q2: 600W 超 → isOutlier=true, isValid=false
    func test_qualityCheck_above600W_outlier() {
        let sample = makeSample(avgWatts: 700.0, durationSec: 60.0, status: .success)
        let result = calculator.qualityCheck(sample)
        XCTAssertTrue(result.isOutlier)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.shouldDisplay) // 表示は可能 (status != fail)
    }

    /// PWR-Q3: partial + avg_watts あり → shouldDisplay=true
    func test_qualityCheck_partial_shouldDisplay() {
        let sample = makeSample(avgWatts: 40.0, durationSec: 60.0, status: .partial)
        let result = calculator.qualityCheck(sample)
        XCTAssertTrue(result.shouldDisplay)
        XCTAssertTrue(result.isValid)
    }

    /// avg_watts=nil → isValid=false, shouldDisplay=false
    func test_qualityCheck_nilWatts_invalid() {
        let sample = makeSample(avgWatts: nil, durationSec: 60.0, status: .missing)
        let result = calculator.qualityCheck(sample)
        XCTAssertFalse(result.isValid)
        XCTAssertFalse(result.shouldDisplay)
    }

    /// 正常サンプル → isValid=true, isOutlier=false, shouldDisplay=true
    func test_qualityCheck_normalSample_allTrue() {
        let sample = makeSample(avgWatts: 42.0, durationSec: 60.0, status: .success)
        let result = calculator.qualityCheck(sample)
        XCTAssertTrue(result.isValid)
        XCTAssertFalse(result.isOutlier)
        XCTAssertTrue(result.shouldDisplay)
    }

    /// fail サンプル → shouldDisplay=false
    func test_qualityCheck_failSample_notDisplayable() {
        let sample = makeSample(avgWatts: 42.0, durationSec: 60.0, status: .fail)
        let result = calculator.qualityCheck(sample)
        XCTAssertFalse(result.shouldDisplay)
    }

    // MARK: - Test Helpers

    private func makeSample(
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
}
