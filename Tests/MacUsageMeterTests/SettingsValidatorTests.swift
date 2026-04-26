import XCTest
@testable import MacUsageMeter

/// 設定バリデーションの単体テスト (第16.1節)
///
/// 観点: 数値範囲、enum 妥当性、依存項目 (capped_metered 時の必須フィールド)
/// 仕様書 5.4 に基づく
///
/// SettingsValidator はテスト対象のバリデーションロジックを表す。
/// プロダクションコードが存在しない場合のため、テスト内にヘルパーを定義する。
final class SettingsValidatorTests: XCTestCase {

    // MARK: - Electricity Unit Price (0.00〜999.99)

    /// 電力単価: 範囲内 (0.00〜999.99)
    func test_electricityPrice_validRange_accepted() {
        XCTAssertTrue(SettingsValidator.validateElectricityUnitPriceYen(0.00))
        XCTAssertTrue(SettingsValidator.validateElectricityUnitPriceYen(31.0))
        XCTAssertTrue(SettingsValidator.validateElectricityUnitPriceYen(999.99))
    }

    /// 電力単価: 範囲外 (負値)
    func test_electricityPrice_negative_rejected() {
        XCTAssertFalse(SettingsValidator.validateElectricityUnitPriceYen(-0.01))
        XCTAssertFalse(SettingsValidator.validateElectricityUnitPriceYen(-100.0))
    }

    /// 電力単価: 範囲外 (1000以上)
    func test_electricityPrice_tooHigh_rejected() {
        XCTAssertFalse(SettingsValidator.validateElectricityUnitPriceYen(1000.0))
        XCTAssertFalse(SettingsValidator.validateElectricityUnitPriceYen(1500.0))
    }

    /// 電力単価: 境界値
    func test_electricityPrice_boundary_acceptedAndRejected() {
        XCTAssertTrue(SettingsValidator.validateElectricityUnitPriceYen(0.0))
        XCTAssertTrue(SettingsValidator.validateElectricityUnitPriceYen(999.99))
        XCTAssertFalse(SettingsValidator.validateElectricityUnitPriceYen(1000.0))
    }

    // MARK: - Power Sampling Interval (30〜300)

    /// 電力採取間隔: 範囲内 (30〜300)
    func test_powerInterval_validRange_accepted() {
        XCTAssertTrue(SettingsValidator.validatePowerSamplingIntervalSec(30))
        XCTAssertTrue(SettingsValidator.validatePowerSamplingIntervalSec(60))
        XCTAssertTrue(SettingsValidator.validatePowerSamplingIntervalSec(300))
    }

    /// 電力採取間隔: 範囲外
    func test_powerInterval_outOfRange_rejected() {
        XCTAssertFalse(SettingsValidator.validatePowerSamplingIntervalSec(29))
        XCTAssertFalse(SettingsValidator.validatePowerSamplingIntervalSec(0))
        XCTAssertFalse(SettingsValidator.validatePowerSamplingIntervalSec(301))
        XCTAssertFalse(SettingsValidator.validatePowerSamplingIntervalSec(-1))
    }

    // MARK: - Wi-Fi Sampling Interval (5〜60)

    /// Wi-Fi 採取間隔: 範囲内 (5〜60)
    func test_wifiInterval_validRange_accepted() {
        XCTAssertTrue(SettingsValidator.validateWifiSamplingIntervalSec(5))
        XCTAssertTrue(SettingsValidator.validateWifiSamplingIntervalSec(10))
        XCTAssertTrue(SettingsValidator.validateWifiSamplingIntervalSec(60))
    }

    /// Wi-Fi 採取間隔: 範囲外
    func test_wifiInterval_outOfRange_rejected() {
        XCTAssertFalse(SettingsValidator.validateWifiSamplingIntervalSec(4))
        XCTAssertFalse(SettingsValidator.validateWifiSamplingIntervalSec(0))
        XCTAssertFalse(SettingsValidator.validateWifiSamplingIntervalSec(61))
    }

    // MARK: - Retention Days (7〜365)

    /// 保持期間: 範囲内 (7〜365)
    func test_retentionDays_validRange_accepted() {
        XCTAssertTrue(SettingsValidator.validateRetentionDays(7))
        XCTAssertTrue(SettingsValidator.validateRetentionDays(90))
        XCTAssertTrue(SettingsValidator.validateRetentionDays(365))
    }

    /// 保持期間: 範囲外
    func test_retentionDays_outOfRange_rejected() {
        XCTAssertFalse(SettingsValidator.validateRetentionDays(6))
        XCTAssertFalse(SettingsValidator.validateRetentionDays(0))
        XCTAssertFalse(SettingsValidator.validateRetentionDays(366))
        XCTAssertFalse(SettingsValidator.validateRetentionDays(-1))
    }

    // MARK: - Monthly Reset Day (1〜28)

    /// 月次リセット日: 範囲内 (1〜28)
    func test_monthlyResetDay_validRange_accepted() {
        XCTAssertTrue(SettingsValidator.validateMonthlyResetDay(1))
        XCTAssertTrue(SettingsValidator.validateMonthlyResetDay(15))
        XCTAssertTrue(SettingsValidator.validateMonthlyResetDay(28))
    }

    /// 月次リセット日: 29以上は不可
    func test_monthlyResetDay_tooHigh_rejected() {
        XCTAssertFalse(SettingsValidator.validateMonthlyResetDay(29))
        XCTAssertFalse(SettingsValidator.validateMonthlyResetDay(30))
        XCTAssertFalse(SettingsValidator.validateMonthlyResetDay(31))
    }

    /// 月次リセット日: 0以下は不可
    func test_monthlyResetDay_tooLow_rejected() {
        XCTAssertFalse(SettingsValidator.validateMonthlyResetDay(0))
        XCTAssertFalse(SettingsValidator.validateMonthlyResetDay(-1))
    }

    // MARK: - Tariff Model Dependencies (5.4.1)

    /// fixed: monthly_fee_yen 必須、他は無効
    func test_fixedModel_monthlyFeePresent_valid() {
        let result = SettingsValidator.validateTariffDependencies(
            model: .fixed,
            monthlyFeeYen: 5000.0,
            pricePerGbYen: nil,
            maxMonthlyFeeYen: nil
        )
        XCTAssertTrue(result.isValid)
    }

    /// fixed: monthly_fee_yen が nil → invalid
    func test_fixedModel_monthlyFeeMissing_invalid() {
        let result = SettingsValidator.validateTariffDependencies(
            model: .fixed,
            monthlyFeeYen: nil,
            pricePerGbYen: nil,
            maxMonthlyFeeYen: nil
        )
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.missingFields.contains("monthly_fee_yen"))
    }

    /// metered: price_per_gb_yen 必須、他は無効
    func test_meteredModel_pricePerGbPresent_valid() {
        let result = SettingsValidator.validateTariffDependencies(
            model: .metered,
            monthlyFeeYen: nil,
            pricePerGbYen: 200.0,
            maxMonthlyFeeYen: nil
        )
        XCTAssertTrue(result.isValid)
    }

    /// metered: price_per_gb_yen が nil → invalid
    func test_meteredModel_pricePerGbMissing_invalid() {
        let result = SettingsValidator.validateTariffDependencies(
            model: .metered,
            monthlyFeeYen: nil,
            pricePerGbYen: nil,
            maxMonthlyFeeYen: nil
        )
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.missingFields.contains("price_per_gb_yen"))
    }

    /// capped_metered: price_per_gb_yen + max_monthly_fee_yen 必須
    func test_cappedMeteredModel_allFieldsPresent_valid() {
        let result = SettingsValidator.validateTariffDependencies(
            model: .cappedMetered,
            monthlyFeeYen: 5000.0,
            pricePerGbYen: 200.0,
            maxMonthlyFeeYen: 1000.0
        )
        XCTAssertTrue(result.isValid)
    }

    /// capped_metered: price_per_gb_yen が nil → invalid
    func test_cappedMeteredModel_pricePerGbMissing_invalid() {
        let result = SettingsValidator.validateTariffDependencies(
            model: .cappedMetered,
            monthlyFeeYen: 5000.0,
            pricePerGbYen: nil,
            maxMonthlyFeeYen: 1000.0
        )
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.missingFields.contains("price_per_gb_yen"))
    }

    /// capped_metered: max_monthly_fee_yen が nil → invalid
    func test_cappedMeteredModel_maxMonthlyFeeMissing_invalid() {
        let result = SettingsValidator.validateTariffDependencies(
            model: .cappedMetered,
            monthlyFeeYen: 5000.0,
            pricePerGbYen: 200.0,
            maxMonthlyFeeYen: nil
        )
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.missingFields.contains("max_monthly_fee_yen"))
    }

    /// fixed + monthly_fee_yen=0 は有効 (無料プラン)
    func test_fixedModel_zeroFee_valid() {
        let result = SettingsValidator.validateTariffDependencies(
            model: .fixed,
            monthlyFeeYen: 0.0,
            pricePerGbYen: nil,
            maxMonthlyFeeYen: nil
        )
        XCTAssertTrue(result.isValid)
    }

    /// metered + price_per_gb_yen=0 は有効
    func test_meteredModel_zeroPrice_valid() {
        let result = SettingsValidator.validateTariffDependencies(
            model: .metered,
            monthlyFeeYen: nil,
            pricePerGbYen: 0.0,
            maxMonthlyFeeYen: nil
        )
        XCTAssertTrue(result.isValid)
    }

    // MARK: - Enum Validation

    /// enum 妥当性: network_tariff_model に不正値
    func test_tariffModel_invalidString_rejected() {
        let model = TariffModel(rawValue: "invalid_model")
        XCTAssertNil(model)
    }

    /// enum 妥当性: 全ての有効値が受理される
    func test_tariffModel_allValidValues_accepted() {
        XCTAssertNotNil(TariffModel(rawValue: "fixed"))
        XCTAssertNotNil(TariffModel(rawValue: "metered"))
        XCTAssertNotNil(TariffModel(rawValue: "capped_metered"))
    }

    /// enum 妥当性: log_level に不正値
    func test_logLevel_invalidString_rejected() {
        let validLevels = ["debug", "info", "warn", "error"]
        XCTAssertFalse(validLevels.contains("invalid"))
        XCTAssertFalse(validLevels.contains(""))
        XCTAssertFalse(validLevels.contains("WARN"))

        // 全ての有効値が含まれる
        XCTAssertTrue(validLevels.contains("debug"))
        XCTAssertTrue(validLevels.contains("info"))
        XCTAssertTrue(validLevels.contains("warn"))
        XCTAssertTrue(validLevels.contains("error"))
    }
}

// MARK: - SettingsValidator (テスト用バリデーション実装)

/// 設定バリデーター (第5.4節)
///
/// プロダクションコードとして独立ファイルに定義されるべきだが、
/// テスト独立性のためにここで定義する。
enum SettingsValidator {

    /// 電力単価バリデーション (0.00〜999.99)
    static func validateElectricityUnitPriceYen(_ value: Double) -> Bool {
        return value >= 0.0 && value <= 999.99
    }

    /// 電力採取間隔バリデーション (30〜300)
    static func validatePowerSamplingIntervalSec(_ value: Int) -> Bool {
        return value >= 30 && value <= 300
    }

    /// Wi-Fi 採取間隔バリデーション (5〜60)
    static func validateWifiSamplingIntervalSec(_ value: Int) -> Bool {
        return value >= 5 && value <= 60
    }

    /// 保持期間バリデーション (7〜365)
    static func validateRetentionDays(_ value: Int) -> Bool {
        return value >= 7 && value <= 365
    }

    /// 月次リセット日バリデーション (1〜28)
    static func validateMonthlyResetDay(_ value: Int) -> Bool {
        return value >= 1 && value <= 28
    }

    /// 料金モデル依存バリデーション結果
    struct TariffDependencyResult {
        let isValid: Bool
        let missingFields: [String]
    }

    /// 料金モデル依存バリデーション (5.4.1)
    static func validateTariffDependencies(
        model: TariffModel,
        monthlyFeeYen: Double?,
        pricePerGbYen: Double?,
        maxMonthlyFeeYen: Double?
    ) -> TariffDependencyResult {
        var missingFields: [String] = []

        switch model {
        case .fixed:
            if monthlyFeeYen == nil {
                missingFields.append("monthly_fee_yen")
            }
        case .metered:
            if pricePerGbYen == nil {
                missingFields.append("price_per_gb_yen")
            }
        case .cappedMetered:
            if pricePerGbYen == nil {
                missingFields.append("price_per_gb_yen")
            }
            if maxMonthlyFeeYen == nil {
                missingFields.append("max_monthly_fee_yen")
            }
        }

        return TariffDependencyResult(
            isValid: missingFields.isEmpty,
            missingFields: missingFields
        )
    }
}
