import XCTest
@testable import MacUsageMeter

/// 料金計算の単体テスト (第16.1節)
///
/// 観点: fixed 日割り、metered 累計、capped_metered 上限適用、月次リセット
/// 仕様書 9.3〜9.4 に基づく
final class TariffCalculatorTests: XCTestCase {

    var calculator: TariffCalculator!

    override func setUp() {
        super.setUp()
        calculator = TariffCalculator()
    }

    // MARK: - Power Cost (9.3)

    /// 電力料金: power_kwh * electricity_unit_price_yen
    /// 例: 1.5 kWh * 31.0 円 = 46.5 円
    func test_powerCost_normalCalc_correctResult() {
        let cost = calculator.calculatePowerCost(powerKwh: 1.5, unitPriceYen: 31.0)
        XCTAssertEqual(cost, 46.5, accuracy: 0.01)
    }

    /// 電力料金: 小数第2位で四捨五入
    /// 例: 1.234 kWh * 31.0 = 38.254 → 38.3 (小数1桁保存)
    func test_powerCost_rounding_roundedToOneDecimal() {
        let cost = calculator.calculatePowerCost(powerKwh: 1.234, unitPriceYen: 31.0)
        // 1.234 * 31.0 = 38.254 → 小数第2位で四捨五入 → 38.3
        XCTAssertEqual(cost, 38.3, accuracy: 0.01)
    }

    /// 電力料金: 0 kWh → 0 円
    func test_powerCost_zeroKwh_zeroCost() {
        let cost = calculator.calculatePowerCost(powerKwh: 0.0, unitPriceYen: 31.0)
        XCTAssertEqual(cost, 0.0, accuracy: 0.01)
    }

    /// 電力料金: 0 円単価 → 0 円
    func test_powerCost_zeroUnitPrice_zeroCost() {
        let cost = calculator.calculatePowerCost(powerKwh: 2.5, unitPriceYen: 0.0)
        XCTAssertEqual(cost, 0.0, accuracy: 0.01)
    }

    // MARK: - Daily Network Cost: fixed (9.4.1)

    /// fixed: monthly_fee_yen / 月の日数 (31日月)
    /// 例: 5000円 / 31日 = 161.3 円
    func test_dailyNetworkCost_fixed31Days_correctDailyAmount() {
        let settings = TariffSettings(
            model: .fixed,
            electricityUnitPriceYen: 31.0,
            monthlyFeeYen: 5000.0,
            pricePerGbYen: nil,
            maxMonthlyFeeYen: nil,
            monthlyResetDay: 1
        )
        let cost = calculator.calculateDailyNetworkCost(wifiGb: 0.5, settings: settings, daysInMonth: 31)
        // 5000 / 31 = 161.290... → 小数第2位で四捨五入 → 161.3
        XCTAssertEqual(cost, 161.3, accuracy: 0.1)
    }

    /// fixed: 30日月
    /// 例: 5000円 / 30日 = 166.7 円
    func test_dailyNetworkCost_fixed30Days_correctDailyAmount() {
        let settings = TariffSettings(
            model: .fixed,
            electricityUnitPriceYen: 31.0,
            monthlyFeeYen: 5000.0,
            pricePerGbYen: nil,
            maxMonthlyFeeYen: nil,
            monthlyResetDay: 1
        )
        let cost = calculator.calculateDailyNetworkCost(wifiGb: 1.0, settings: settings, daysInMonth: 30)
        // 5000 / 30 = 166.666... → 166.7
        XCTAssertEqual(cost, 166.7, accuracy: 0.1)
    }

    /// fixed: 28日月 (2月)
    /// 例: 5000円 / 28日 = 178.6 円
    func test_dailyNetworkCost_fixed28Days_correctDailyAmount() {
        let settings = TariffSettings(
            model: .fixed,
            electricityUnitPriceYen: 31.0,
            monthlyFeeYen: 5000.0,
            pricePerGbYen: nil,
            maxMonthlyFeeYen: nil,
            monthlyResetDay: 1
        )
        let cost = calculator.calculateDailyNetworkCost(wifiGb: 0.0, settings: settings, daysInMonth: 28)
        // 5000 / 28 = 178.571... → 178.6
        XCTAssertEqual(cost, 178.6, accuracy: 0.1)
    }

    // MARK: - Daily Network Cost: metered (9.4.1)

    /// metered: wifi_gb * price_per_gb_yen
    /// 例: 1.5 GB * 200 円 = 300 円
    func test_dailyNetworkCost_metered_correctAmount() {
        let settings = TariffSettings(
            model: .metered,
            electricityUnitPriceYen: 31.0,
            monthlyFeeYen: nil,
            pricePerGbYen: 200.0,
            maxMonthlyFeeYen: nil,
            monthlyResetDay: 1
        )
        let cost = calculator.calculateDailyNetworkCost(wifiGb: 1.5, settings: settings, daysInMonth: 31)
        XCTAssertEqual(cost, 300.0, accuracy: 0.01)
    }

    /// metered: 0 GB → 0 円
    func test_dailyNetworkCost_meteredZeroGb_zeroCost() {
        let settings = TariffSettings(
            model: .metered,
            electricityUnitPriceYen: 31.0,
            monthlyFeeYen: nil,
            pricePerGbYen: 200.0,
            maxMonthlyFeeYen: nil,
            monthlyResetDay: 1
        )
        let cost = calculator.calculateDailyNetworkCost(wifiGb: 0.0, settings: settings, daysInMonth: 31)
        XCTAssertEqual(cost, 0.0, accuracy: 0.01)
    }

    // MARK: - Daily Network Cost: capped_metered (9.4.1)

    /// capped_metered 日次: wifi_gb * price_per_gb_yen (上限なし)
    /// 上限制御は月次側で行う
    func test_dailyNetworkCost_cappedMetered_noCapAppliedDaily() {
        let settings = TariffSettings(
            model: .cappedMetered,
            electricityUnitPriceYen: 31.0,
            monthlyFeeYen: 5000.0,
            pricePerGbYen: 200.0,
            maxMonthlyFeeYen: 1000.0,
            monthlyResetDay: 1
        )
        // 日次は上限なし → 3.0 * 200 = 600
        let cost = calculator.calculateDailyNetworkCost(wifiGb: 3.0, settings: settings, daysInMonth: 31)
        XCTAssertEqual(cost, 600.0, accuracy: 0.01)
    }

    // MARK: - Monthly Network Cost: fixed (9.4.2)

    /// fixed 月次: SUM(daily_rollups.network_cost_yen)
    func test_monthlyNetworkCost_fixed_sumOfDailyCosts() {
        let settings = TariffSettings(
            model: .fixed,
            electricityUnitPriceYen: 31.0,
            monthlyFeeYen: 5000.0,
            pricePerGbYen: nil,
            maxMonthlyFeeYen: nil,
            monthlyResetDay: 1
        )
        // 10日分の日次合計 = 1613.0 (10 * 161.3)
        let cost = calculator.calculateMonthlyNetworkCost(
            totalWifiGb: 5.0,
            totalDailyNetworkCost: 1613.0,
            settings: settings
        )
        XCTAssertEqual(cost, 1613.0, accuracy: 0.01)
    }

    // MARK: - Monthly Network Cost: metered (9.4.2)

    /// metered 月次: 累計 wifi_gb * price_per_gb_yen
    func test_monthlyNetworkCost_metered_totalGbTimesPrice() {
        let settings = TariffSettings(
            model: .metered,
            electricityUnitPriceYen: 31.0,
            monthlyFeeYen: nil,
            pricePerGbYen: 200.0,
            maxMonthlyFeeYen: nil,
            monthlyResetDay: 1
        )
        // 累計 10.5 GB * 200 = 2100
        let cost = calculator.calculateMonthlyNetworkCost(
            totalWifiGb: 10.5,
            totalDailyNetworkCost: 0.0,
            settings: settings
        )
        XCTAssertEqual(cost, 2100.0, accuracy: 0.01)
    }

    // MARK: - Monthly Network Cost: capped_metered (9.4.2)

    /// capped_metered 月次: min(累計 wifi_gb * price_per_gb_yen, max_monthly_fee_yen)
    /// AT-16: 月 10GB、GB単価 200円、上限 1000円で 8GB 使用 → 1000円 (上限適用)
    func test_monthlyNetworkCost_cappedMetered_capApplied() {
        let settings = TariffSettings(
            model: .cappedMetered,
            electricityUnitPriceYen: 31.0,
            monthlyFeeYen: 5000.0,
            pricePerGbYen: 200.0,
            maxMonthlyFeeYen: 1000.0,
            monthlyResetDay: 1
        )
        // 累計 8 GB * 200 = 1600 → min(1600, 1000) = 1000
        let cost = calculator.calculateMonthlyNetworkCost(
            totalWifiGb: 8.0,
            totalDailyNetworkCost: 0.0,
            settings: settings
        )
        XCTAssertEqual(cost, 1000.0, accuracy: 0.01)
    }

    /// capped_metered 月次: 上限未達の場合
    func test_monthlyNetworkCost_cappedMetered_belowCap() {
        let settings = TariffSettings(
            model: .cappedMetered,
            electricityUnitPriceYen: 31.0,
            monthlyFeeYen: 5000.0,
            pricePerGbYen: 200.0,
            maxMonthlyFeeYen: 1000.0,
            monthlyResetDay: 1
        )
        // 累計 3 GB * 200 = 600 → min(600, 1000) = 600
        let cost = calculator.calculateMonthlyNetworkCost(
            totalWifiGb: 3.0,
            totalDailyNetworkCost: 0.0,
            settings: settings
        )
        XCTAssertEqual(cost, 600.0, accuracy: 0.01)
    }

    // MARK: - Rounding Rules (9.7)

    /// 丸め規則: network_cost_yen は小数第2位で四捨五入
    func test_rounding_networkCost_roundedCorrectly() {
        let settings = TariffSettings(
            model: .metered,
            electricityUnitPriceYen: 31.0,
            monthlyFeeYen: nil,
            pricePerGbYen: 33.33,
            maxMonthlyFeeYen: nil,
            monthlyResetDay: 1
        )
        // 1.0 GB * 33.33 = 33.33 → そのまま
        let cost = calculator.calculateDailyNetworkCost(wifiGb: 1.0, settings: settings, daysInMonth: 31)
        XCTAssertEqual(cost, 33.3, accuracy: 0.1)
    }

    // MARK: - Zero Yen Validity

    /// 0 円の有効性: fixed + monthly_fee_yen=0 は有効 (無料プラン)
    func test_dailyNetworkCost_fixedZeroFee_zeroCost() {
        let settings = TariffSettings(
            model: .fixed,
            electricityUnitPriceYen: 31.0,
            monthlyFeeYen: 0.0,
            pricePerGbYen: nil,
            maxMonthlyFeeYen: nil,
            monthlyResetDay: 1
        )
        let cost = calculator.calculateDailyNetworkCost(wifiGb: 5.0, settings: settings, daysInMonth: 31)
        XCTAssertEqual(cost, 0.0, accuracy: 0.01)
    }

    /// 0 円の有効性: metered + price_per_gb_yen=0 は有効
    func test_dailyNetworkCost_meteredZeroPrice_zeroCost() {
        let settings = TariffSettings(
            model: .metered,
            electricityUnitPriceYen: 31.0,
            monthlyFeeYen: nil,
            pricePerGbYen: 0.0,
            maxMonthlyFeeYen: nil,
            monthlyResetDay: 1
        )
        let cost = calculator.calculateDailyNetworkCost(wifiGb: 10.0, settings: settings, daysInMonth: 31)
        XCTAssertEqual(cost, 0.0, accuracy: 0.01)
    }

    // MARK: - Monthly Total (9.6)

    /// 月次合計: 月次電力料金 + 月次通信料金
    func test_monthlyTotal_sumOfPowerAndNetwork() {
        let total = calculator.calculateMonthlyTotalCost(
            monthlyPowerCostYen: 1500.0,
            monthlyNetworkCostYen: 2000.0
        )
        XCTAssertEqual(total, 3500.0, accuracy: 0.01)
    }
}
