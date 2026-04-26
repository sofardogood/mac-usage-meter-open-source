import XCTest
@testable import MacUsageMeter

/// CoverageRatio 計算の単体テスト (第16.1節)
///
/// 観点: 電力・Wi-Fi の coverage ratio、当日/完了日の区別、丸め・クランプ
/// 仕様書 9.2 に基づく
final class CoverageRatioCalculatorTests: XCTestCase {

    var calculator: CoverageRatioCalculator!

    override func setUp() {
        super.setUp()
        calculator = CoverageRatioCalculator()
    }

    // MARK: - Power Coverage

    /// 完了日: 86400秒、60秒間隔、1440サンプル → ratio=1.0
    func test_powerCoverage_fullDay1440Samples_ratioOne() {
        let ratio = calculator.calculatePower(
            validSampleCount: 1440,
            targetSeconds: CoverageRatioCalculator.fullDaySeconds,
            samplingIntervalSec: 60
        )
        XCTAssertEqual(ratio, 1.0, accuracy: 0.001)
    }

    /// 完了日: 86400秒、60秒間隔、720サンプル → ratio=0.5
    func test_powerCoverage_halfDay720Samples_ratioHalf() {
        let ratio = calculator.calculatePower(
            validSampleCount: 720,
            targetSeconds: CoverageRatioCalculator.fullDaySeconds,
            samplingIntervalSec: 60
        )
        XCTAssertEqual(ratio, 0.5, accuracy: 0.001)
    }

    /// 完了日: サンプル 0 件 → ratio=0.0
    func test_powerCoverage_noSamples_ratioZero() {
        let ratio = calculator.calculatePower(
            validSampleCount: 0,
            targetSeconds: CoverageRatioCalculator.fullDaySeconds,
            samplingIntervalSec: 60
        )
        XCTAssertEqual(ratio, 0.0, accuracy: 0.001)
    }

    /// 30秒間隔、2880サンプル → ratio=1.0
    func test_powerCoverage_30secInterval_fullDay_ratioOne() {
        // floor(86400 / 30) = 2880
        let ratio = calculator.calculatePower(
            validSampleCount: 2880,
            targetSeconds: CoverageRatioCalculator.fullDaySeconds,
            samplingIntervalSec: 30
        )
        XCTAssertEqual(ratio, 1.0, accuracy: 0.001)
    }

    /// 300秒間隔、288サンプル → ratio=1.0
    func test_powerCoverage_300secInterval_fullDay_ratioOne() {
        // floor(86400 / 300) = 288
        let ratio = calculator.calculatePower(
            validSampleCount: 288,
            targetSeconds: CoverageRatioCalculator.fullDaySeconds,
            samplingIntervalSec: 300
        )
        XCTAssertEqual(ratio, 1.0, accuracy: 0.001)
    }

    // MARK: - Wi-Fi Coverage

    /// 完了日: 86400秒、10秒間隔、8640サンプル → ratio=1.0
    func test_wifiCoverage_fullDay8640Samples_ratioOne() {
        let ratio = calculator.calculateWifi(
            validSampleCount: 8640,
            targetSeconds: CoverageRatioCalculator.fullDaySeconds,
            samplingIntervalSec: 10
        )
        XCTAssertEqual(ratio, 1.0, accuracy: 0.001)
    }

    /// 5秒間隔、17280サンプル → ratio=1.0
    func test_wifiCoverage_5secInterval_fullDay_ratioOne() {
        // floor(86400 / 5) = 17280
        let ratio = calculator.calculateWifi(
            validSampleCount: 17280,
            targetSeconds: CoverageRatioCalculator.fullDaySeconds,
            samplingIntervalSec: 5
        )
        XCTAssertEqual(ratio, 1.0, accuracy: 0.001)
    }

    /// Wi-Fi 半分のサンプル → 0.5
    func test_wifiCoverage_halfSamples_ratioHalf() {
        let ratio = calculator.calculateWifi(
            validSampleCount: 4320,
            targetSeconds: CoverageRatioCalculator.fullDaySeconds,
            samplingIntervalSec: 10
        )
        XCTAssertEqual(ratio, 0.5, accuracy: 0.001)
    }

    // MARK: - Clamping

    /// 1.0 超 (間隔短縮で起こりうる) → 1.0 に切り詰め
    func test_clamp_aboveOne_clampedToOne() {
        // 設定変更で間隔が 60s→30s に変わった場合、前半60s間隔、後半30s間隔で
        // 合計サンプル数が期待を超えるケース
        let ratio = calculator.calculatePower(
            validSampleCount: 2000,
            targetSeconds: CoverageRatioCalculator.fullDaySeconds,
            samplingIntervalSec: 60
        )
        // 2000 / 1440 = 1.389 → 1.0 に切り詰め
        XCTAssertEqual(ratio, 1.0, accuracy: 0.001)
    }

    /// clampAndRound: 1.5 → 1.0
    func test_clampAndRound_aboveOne_clampedToOne() {
        let result = calculator.clampAndRound(1.5)
        XCTAssertEqual(result, 1.0, accuracy: 0.001)
    }

    /// clampAndRound: -0.1 → 0.0 (負値は起こりにくいが安全策)
    func test_clampAndRound_negative_clampedToZero() {
        let result = calculator.clampAndRound(-0.1)
        XCTAssertEqual(result, 0.0, accuracy: 0.001)
    }

    // MARK: - Rounding

    /// 小数第4位で四捨五入 (3桁保持)
    /// 1000 / 1440 = 0.694444... → 0.694
    func test_rounding_fourthDecimalRoundedDown() {
        let result = calculator.clampAndRound(0.694444)
        XCTAssertEqual(result, 0.694, accuracy: 0.0001)
    }

    /// 0.6945 → 0.695 (四捨五入で切り上げ)
    func test_rounding_fourthDecimalRoundedUp() {
        let result = calculator.clampAndRound(0.6945)
        XCTAssertEqual(result, 0.695, accuracy: 0.0001)
    }

    /// 0.9999 → 1.0 (四捨五入で1.0)
    func test_rounding_nearOne_roundedToOne() {
        let result = calculator.clampAndRound(0.9999)
        XCTAssertEqual(result, 1.0, accuracy: 0.001)
    }

    // MARK: - Current Day

    /// 当日: 経過秒数ベースでの coverage ratio
    /// 3600秒経過 (1時間)、60秒間隔 → 期待 floor(3600/60)=60 件
    /// 45件有効 → 45/60 = 0.75
    func test_currentDay_elapsed3600sec_correctRatio() {
        let ratio = calculator.calculatePower(
            validSampleCount: 45,
            targetSeconds: 3600,
            samplingIntervalSec: 60
        )
        XCTAssertEqual(ratio, 0.75, accuracy: 0.001)
    }

    /// 当日: 経過秒数が非常に短い場合 (60秒、1サンプル期待)
    func test_currentDay_elapsed60sec_oneExpectedSample() {
        let ratio = calculator.calculatePower(
            validSampleCount: 1,
            targetSeconds: 60,
            samplingIntervalSec: 60
        )
        XCTAssertEqual(ratio, 1.0, accuracy: 0.001)
    }

    /// 当日: 経過秒数が間隔未満の場合 (30秒経過、60秒間隔 → 期待0件)
    /// 期待0件の場合、0除算を避けて0.0を返す
    func test_currentDay_elapsedLessThanInterval_ratioZero() {
        let ratio = calculator.calculatePower(
            validSampleCount: 0,
            targetSeconds: 30,
            samplingIntervalSec: 60
        )
        XCTAssertEqual(ratio, 0.0, accuracy: 0.001)
    }

    /// fullDaySeconds が 86400 であることの確認
    func test_fullDaySeconds_is86400() {
        XCTAssertEqual(CoverageRatioCalculator.fullDaySeconds, 86_400)
    }
}
