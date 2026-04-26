import Foundation

/// 料金計算器 (第9章)
///
/// 電力料金と通信料金を計算する。
/// 日次 (daily_rollups) と月次 (表示用) の2段階で計算する。
struct TariffCalculator: Sendable {

    // MARK: - Power Cost

    /// 電力料金を計算する
    func calculatePowerCost(powerKwh: Double, unitPriceYen: Double) -> Double {
        return powerKwh * unitPriceYen
    }

    // MARK: - Daily Network Cost

    /// 日次通信料金を計算する
    func calculateDailyNetworkCost(wifiGb: Double, settings: TariffSettings, daysInMonth: Int) -> Double {
        switch settings.model {
        case .fixed:
            let fee = settings.monthlyFeeYen ?? 0.0
            return daysInMonth > 0 ? fee / Double(daysInMonth) : 0.0
        case .metered:
            let price = settings.pricePerGbYen ?? 0.0
            return wifiGb * price
        case .cappedMetered:
            let price = settings.pricePerGbYen ?? 0.0
            return wifiGb * price
        }
    }

    // MARK: - Monthly Network Cost

    /// 月次通信料金を計算する
    func calculateMonthlyNetworkCost(
        totalWifiGb: Double,
        totalDailyNetworkCost: Double,
        settings: TariffSettings
    ) -> Double {
        switch settings.model {
        case .fixed:
            return totalDailyNetworkCost
        case .metered:
            let price = settings.pricePerGbYen ?? 0.0
            return totalWifiGb * price
        case .cappedMetered:
            let price = settings.pricePerGbYen ?? 0.0
            let maxFee = settings.maxMonthlyFeeYen ?? Double.greatestFiniteMagnitude
            return min(totalWifiGb * price, maxFee)
        }
    }

    // MARK: - Monthly Total

    /// 月次合計料金を計算する
    func calculateMonthlyTotalCost(monthlyPowerCostYen: Double, monthlyNetworkCostYen: Double) -> Double {
        return monthlyPowerCostYen + monthlyNetworkCostYen
    }
}
