import Foundation

/// 電力量 (kWh) 計算器 (第9.1節)
///
/// 電力サンプル群から日次の電力量を算出する。
struct PowerKwhCalculator: Sendable {

    /// 外れ値閾値 (W)。PWR-Q2: 600W 超で outlier_flag=1
    static let outlierThresholdWatts: Double = 600.0

    /// 電力量 (kWh) を計算する
    ///
    /// ```
    /// power_kwh = Sigma(avg_watts_i * sample_duration_sec_i) / 3,600,000
    /// ```
    ///
    /// 除外条件:
    /// - status が fail
    /// - outlier_flag = 1
    /// - avg_watts が nil
    ///
    /// status = partial は avg_watts が非 nil なら含める。
    /// status = stale は含める。
    ///
    /// - Parameter samples: 対象日の電力サンプル群
    /// - Returns: 電力量 (kWh)。小数第6位で四捨五入
    func calculate(from samples: [PowerSample]) -> Double {
        var totalWattSeconds: Double = 0.0
        for sample in samples {
            guard isValidForAggregation(sample) else { continue }
            guard let watts = sample.avgWatts else { continue }
            totalWattSeconds += watts * sample.sampleDurationSec
        }
        let kwh = totalWattSeconds / 3_600_000.0
        // 小数第6位で四捨五入 → 小数5桁保持
        return (kwh * 100_000).rounded() / 100_000
    }

    /// サンプルが集計対象かどうかを判定する
    ///
    /// - Parameter sample: 電力サンプル
    /// - Returns: 集計に含めるなら true
    func isValidForAggregation(_ sample: PowerSample) -> Bool {
        // 除外: status=fail
        if sample.status == .fail { return false }
        // 除外: outlier_flag=1
        if sample.outlierFlag == 1 { return false }
        // 除外: avg_watts が nil
        if sample.avgWatts == nil { return false }
        return true
    }

    /// 外れ値判定を行う
    ///
    /// - Parameter avgWatts: 平均電力 (W)
    /// - Returns: 外れ値なら true (600W 超)
    func isOutlier(_ avgWatts: Double) -> Bool {
        return avgWatts > Self.outlierThresholdWatts
    }

    /// データ品質チェックを行う (第7.6節)
    ///
    /// - PWR-Q1: avg_watts < 0 → status=fail
    /// - PWR-Q2: avg_watts > 600 → outlier_flag=1
    /// - PWR-Q3: parser_status=partial かつ avg_watts あり → 電力表示は許可
    ///
    /// - Parameter sample: 電力サンプル
    /// - Returns: 品質チェック結果
    func qualityCheck(_ sample: PowerSample) -> QualityCheckResult {
        guard let watts = sample.avgWatts else {
            return QualityCheckResult(isValid: false, isOutlier: false, shouldDisplay: false)
        }
        // PWR-Q1: 負値は fail
        if watts < 0 {
            return QualityCheckResult(isValid: false, isOutlier: false, shouldDisplay: false)
        }
        // PWR-Q2: 600W 超は outlier
        let outlier = isOutlier(watts)
        // PWR-Q3: partial かつ avg_watts あり → 表示可
        let shouldDisplay = sample.status != .fail
        return QualityCheckResult(isValid: !outlier && sample.status != .fail, isOutlier: outlier, shouldDisplay: shouldDisplay)
    }

    /// 品質チェック結果
    struct QualityCheckResult: Sendable {
        let isValid: Bool
        let isOutlier: Bool
        let shouldDisplay: Bool
    }
}
