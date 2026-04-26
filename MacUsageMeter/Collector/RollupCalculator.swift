import Foundation

/// ロールアップ計算器 (第9章)
///
/// 生サンプルから日次集計値を計算する。
/// power_kwh, wifi_gb, coverage_ratio, コスト を算出する。
struct RollupCalculator: Sendable {

    private let powerKwhCalculator = PowerKwhCalculator()
    private let coverageRatioCalculator = CoverageRatioCalculator()
    private let tariffCalculator = TariffCalculator()

    // MARK: - Power Rollup

    /// 電力量 (kWh) を計算する (第9.1節)
    ///
    /// ```
    /// power_kwh = Sigma(avg_watts_i * sample_duration_sec_i) / 3,600,000
    /// ```
    ///
    /// 除外条件:
    /// - status が fail のもの
    /// - outlier_flag = 1 のもの
    /// - avg_watts が nil のもの
    ///
    /// status = partial は avg_watts が非 nil なら含める。
    /// status = stale は含める。
    ///
    /// - Parameter samples: 対象日の電力サンプル群
    /// - Returns: 電力量 (kWh)。小数第6位で四捨五入
    func calculatePowerKwh(from samples: [PowerSample]) -> Double {
        return powerKwhCalculator.calculate(from: samples)
    }

    /// 電力 coverage ratio を計算する (第9.2節)
    ///
    /// - Parameters:
    ///   - validSampleCount: 集計に含めたサンプル件数
    ///   - targetSeconds: 集計対象秒数 (完了日: 86400秒固定、当日: 経過秒数)
    ///   - samplingIntervalSec: 電力採取間隔 (秒)
    /// - Returns: coverage ratio (0.0〜1.0)。小数第4位で四捨五入、1.0超は1.0に切り詰め
    func calculateCoverageRatio(validSampleCount: Int, targetSeconds: Int, samplingIntervalSec: Int) -> Double {
        return coverageRatioCalculator.calculatePower(
            validSampleCount: validSampleCount,
            targetSeconds: targetSeconds,
            samplingIntervalSec: samplingIntervalSec
        )
    }

    // MARK: - Wi-Fi Rollup

    /// Wi-Fi 使用量 (GB) を計算する (第8.3節)
    ///
    /// ```
    /// wifi_gb = Sigma(sent_bytes_delta + recv_bytes_delta) / 1,000,000,000
    /// ```
    ///
    /// 1 GB = 10^9 bytes (SI 基準)
    ///
    /// - Parameter samples: 対象日の Wi-Fi サンプル群
    /// - Returns: Wi-Fi 使用量 (GB)。小数第4位で四捨五入
    func calculateWifiGb(from samples: [WifiSample]) -> Double {
        let validSamples = samples.filter { $0.status == .success }
        let totalBytes: Int64 = validSamples.reduce(0) { $0 + $1.sentBytesDelta + $1.recvBytesDelta }
        let gb = Double(totalBytes) / 1_000_000_000.0
        // 小数第4位で四捨五入 → 小数3桁保持
        return (gb * 1000).rounded() / 1000
    }

    // MARK: - Full Rollup

    /// 日次ロールアップを計算する (デフォルト間隔版)
    ///
    /// 完全版の `calculateRollup(dateLocal:powerSamples:wifiSamples:tariffSettings:targetSeconds:powerSamplingIntervalSec:wifiSamplingIntervalSec:)` に
    /// デフォルトの採取間隔 (電力=60秒、Wi-Fi=10秒) を渡す便利メソッド。
    ///
    /// - Parameters:
    ///   - dateLocal: 対象日 (YYYY-MM-DD)
    ///   - powerSamples: 対象日の電力サンプル群
    ///   - wifiSamples: 対象日の Wi-Fi サンプル群
    ///   - tariffSettings: 料金設定
    ///   - targetSeconds: 集計対象秒数
    /// - Returns: 日次ロールアップ
    func calculateRollup(
        dateLocal: String,
        powerSamples: [PowerSample],
        wifiSamples: [WifiSample],
        tariffSettings: TariffSettings,
        targetSeconds: Int
    ) -> DailyRollup {
        return calculateRollup(
            dateLocal: dateLocal,
            powerSamples: powerSamples,
            wifiSamples: wifiSamples,
            tariffSettings: tariffSettings,
            targetSeconds: targetSeconds,
            powerSamplingIntervalSec: 60,
            wifiSamplingIntervalSec: 10
        )
    }

    /// sampling interval を指定できる完全版ロールアップ
    func calculateRollup(
        dateLocal: String,
        powerSamples: [PowerSample],
        wifiSamples: [WifiSample],
        tariffSettings: TariffSettings,
        targetSeconds: Int,
        powerSamplingIntervalSec: Int,
        wifiSamplingIntervalSec: Int
    ) -> DailyRollup {
        // 電力集計
        let powerKwh = calculatePowerKwh(from: powerSamples)
        let validPowerCount = powerSamples.filter { powerKwhCalculator.isValidForAggregation($0) }.count
        let coverageRatioPower = coverageRatioCalculator.calculatePower(
            validSampleCount: validPowerCount,
            targetSeconds: targetSeconds,
            samplingIntervalSec: powerSamplingIntervalSec
        )

        // Wi-Fi 集計
        let wifiGb = calculateWifiGb(from: wifiSamples)
        let validWifiCount = wifiSamples.filter { $0.status == .success }.count
        let coverageRatioWifi = coverageRatioCalculator.calculateWifi(
            validSampleCount: validWifiCount,
            targetSeconds: targetSeconds,
            samplingIntervalSec: wifiSamplingIntervalSec
        )

        // 電力料金
        let powerCostYen = tariffCalculator.calculatePowerCost(
            powerKwh: powerKwh,
            unitPriceYen: tariffSettings.electricityUnitPriceYen
        )

        // 通信料金 (日次)
        let daysInMonth = Self.daysInMonth(for: dateLocal)
        let networkCostYen = tariffCalculator.calculateDailyNetworkCost(
            wifiGb: wifiGb,
            settings: tariffSettings,
            daysInMonth: daysInMonth
        )

        let now = Int64(Date().timeIntervalSince1970 * 1000)

        return DailyRollup(
            dateLocal: dateLocal,
            powerKwh: validPowerCount > 0 ? powerKwh : nil,
            wifiGb: validWifiCount > 0 ? wifiGb : nil,
            powerCostYen: validPowerCount > 0 ? powerCostYen : nil,
            networkCostYen: validWifiCount > 0 ? networkCostYen : nil,
            coverageRatioPower: coverageRatioPower,
            coverageRatioWifi: coverageRatioWifi,
            sampleCountPower: validPowerCount,
            sampleCountWifi: validWifiCount,
            computedAtMs: now
        )
    }

    // MARK: - Helpers

    /// 日付文字列 (YYYY-MM-DD) から当月の日数を返す
    static func daysInMonth(for dateLocal: String) -> Int {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = formatter.date(from: dateLocal) else { return 30 }
        let calendar = Calendar.current
        return calendar.range(of: .day, in: .month, for: date)?.count ?? 30
    }
}
