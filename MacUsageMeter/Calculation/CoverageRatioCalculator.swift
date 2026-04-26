import Foundation

/// Coverage Ratio 計算器 (第9.2節)
///
/// 計測期間中に有効サンプルが存在する割合を 0.0〜1.0 で算出する。
struct CoverageRatioCalculator: Sendable {

    /// 完了日の集計対象秒数 (86,400秒 = 24時間固定)
    /// sleep 除外なし。sleep 中はサンプルが存在しないため coverage_ratio に反映される。
    static let fullDaySeconds: Int = 86_400

    /// 電力 coverage ratio を計算する
    ///
    /// ```
    /// coverage_ratio_power = 有効サンプル数 / floor(集計対象秒数 / power_sampling_interval_sec)
    /// ```
    ///
    /// - Parameters:
    ///   - validSampleCount: 集計に含めた電力サンプル件数
    ///   - targetSeconds: 集計対象秒数 (完了日: 86400, 当日: 経過秒数)
    ///   - samplingIntervalSec: 電力採取間隔 (秒)
    /// - Returns: coverage ratio (0.0〜1.0)。小数第4位で四捨五入、1.0超は1.0に切り詰め
    func calculatePower(validSampleCount: Int, targetSeconds: Int, samplingIntervalSec: Int) -> Double {
        return calculate(validSampleCount: validSampleCount, targetSeconds: targetSeconds, samplingIntervalSec: samplingIntervalSec)
    }

    /// Wi-Fi coverage ratio を計算する
    ///
    /// ```
    /// coverage_ratio_wifi = 有効 wifi_samples 数 / floor(集計対象秒数 / wifi_sampling_interval_sec)
    /// ```
    ///
    /// - Parameters:
    ///   - validSampleCount: 集計に含めた Wi-Fi サンプル件数
    ///   - targetSeconds: 集計対象秒数
    ///   - samplingIntervalSec: Wi-Fi 採取間隔 (秒)
    /// - Returns: coverage ratio (0.0〜1.0)
    func calculateWifi(validSampleCount: Int, targetSeconds: Int, samplingIntervalSec: Int) -> Double {
        return calculate(validSampleCount: validSampleCount, targetSeconds: targetSeconds, samplingIntervalSec: samplingIntervalSec)
    }

    /// 当日の集計対象秒数を算出する
    ///
    /// 当日 00:00:00 (ローカル) から現在時刻までの経過秒数。
    ///
    /// - Returns: 経過秒数
    func currentDayElapsedSeconds() -> Int {
        let now = Date()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        let elapsed = now.timeIntervalSince(startOfDay)
        return max(1, Int(elapsed))
    }

    /// 丸め処理: 小数第4位で四捨五入、1.0超は1.0に切り詰め
    ///
    /// - Parameter value: 丸め前の値
    /// - Returns: 丸め後の値 (0.0〜1.0)
    func clampAndRound(_ value: Double) -> Double {
        let rounded = (value * 1000).rounded() / 1000
        return min(max(rounded, 0.0), 1.0)
    }

    // MARK: - Private

    private func calculate(validSampleCount: Int, targetSeconds: Int, samplingIntervalSec: Int) -> Double {
        guard samplingIntervalSec > 0, targetSeconds > 0 else { return 0.0 }
        let expectedSamples = Double(targetSeconds) / Double(samplingIntervalSec)
        let floored = floor(expectedSamples)
        guard floored > 0 else { return 0.0 }
        let ratio = Double(validSampleCount) / floored
        return clampAndRound(ratio)
    }
}
