import Foundation

/// powermetrics plist パーサー (第7.2節)
///
/// powermetrics の `-f plist` 出力をパースし、正規化した値を返す。
/// ルートは配列で、最後の要素 (最新サンプル) を取得する。
public struct PowerMetricsParser: Sendable {

    // MARK: - Parse

    /// plist 出力をパースする
    ///
    /// パース優先順位 (7.2.3):
    /// 1. processor.combined_power → Apple Silicon (mW → W 変換)
    /// 2. processor.package_power → Intel (W のまま)
    /// 3. いずれもなし → source_level=C (欠測)
    ///
    /// - Parameter plistData: plist XML 文字列
    /// - Returns: パース結果
    public func parse(_ plistData: String) -> ParseResult {
        guard let data = plistData.data(using: .utf8) else {
            return failResult(message: "Cannot convert plist to data")
        }

        // plist をデシリアライズ
        let plistObj: Any
        do {
            plistObj = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            return failResult(message: "PropertyListSerialization failed: \(error.localizedDescription)")
        }

        // ルートは配列
        guard let array = plistObj as? [[String: Any]], let sample = array.last else {
            // ルートが辞書の場合もある (一部バージョン)
            if let dict = plistObj as? [String: Any] {
                return parseSample(dict)
            }
            return failResult(message: "Root is not an array or dictionary")
        }

        return parseSample(sample)
    }

    // MARK: - Private

    private func parseSample(_ sample: [String: Any]) -> ParseResult {
        guard let processor = sample["processor"] as? [String: Any] else {
            return failResult(message: "No 'processor' key in sample")
        }

        // elapsed_ns はサンプルのトップレベル
        let sampleDurationSec: Double?
        if let elapsedNs = sample["elapsed_ns"] as? NSNumber {
            sampleDurationSec = elapsedNs.doubleValue / 1_000_000_000.0
        } else {
            sampleDurationSec = nil
        }

        // パース優先順位:
        // 1. combined_power → Apple Silicon
        if let combinedPower = processor["combined_power"] as? NSNumber {
            return parseAppleSilicon(processor, combinedPowerMw: combinedPower.doubleValue, sampleDurationSec: sampleDurationSec)
        }

        // 2. package_power → Intel
        if let packagePower = processor["package_power"] as? NSNumber {
            return parseIntelFromValues(packagePowerW: packagePower.doubleValue, sampleDurationSec: sampleDurationSec)
        }

        // 3. cpu_power のみ → source_level B
        if let cpuPower = processor["cpu_power"] as? NSNumber {
            let cpuWatts = cpuPower.doubleValue / 1000.0 // Apple Silicon の場合 mW
            return ParseResult(
                hardwareFamily: .unknown,
                sourceLevel: "B",
                parserStatus: "partial",
                avgWatts: nil,
                cpuWatts: cpuWatts,
                gpuWatts: nil,
                aneWatts: nil,
                sampleDurationSec: sampleDurationSec,
                missingKeys: ["combined_power", "package_power"]
            )
        }

        // 4. いずれも取得不可 → source_level C
        return ParseResult(
            hardwareFamily: .unknown,
            sourceLevel: "C",
            parserStatus: "fail",
            avgWatts: nil,
            cpuWatts: nil,
            gpuWatts: nil,
            aneWatts: nil,
            sampleDurationSec: sampleDurationSec,
            missingKeys: ["combined_power", "package_power", "cpu_power"]
        )
    }

    // MARK: - Apple Silicon

    /// Apple Silicon の plist をパースする (7.2.1)
    public func parseAppleSilicon(_ sample: [String: Any]) -> ParseResult {
        guard let processor = sample["processor"] as? [String: Any] else {
            return failResult(message: "No 'processor' key")
        }
        let combinedPower = (processor["combined_power"] as? NSNumber)?.doubleValue
        let sampleDurationSec: Double?
        if let elapsedNs = sample["elapsed_ns"] as? NSNumber {
            sampleDurationSec = elapsedNs.doubleValue / 1_000_000_000.0
        } else {
            sampleDurationSec = nil
        }

        if let mw = combinedPower {
            return parseAppleSilicon(processor, combinedPowerMw: mw, sampleDurationSec: sampleDurationSec)
        }
        return failResult(message: "No combined_power in Apple Silicon sample")
    }

    private func parseAppleSilicon(_ processor: [String: Any], combinedPowerMw: Double, sampleDurationSec: Double?) -> ParseResult {
        // mW → W 変換
        let avgWatts = combinedPowerMw / 1000.0

        var missingKeys: [String] = []
        var parserStatus = "success"

        // 任意キー
        let cpuWatts: Double?
        if let v = processor["cpu_power"] as? NSNumber {
            cpuWatts = v.doubleValue / 1000.0
        } else {
            cpuWatts = nil
            missingKeys.append("cpu_power")
        }

        let gpuWatts: Double?
        if let v = processor["gpu_power"] as? NSNumber {
            gpuWatts = v.doubleValue / 1000.0
        } else {
            gpuWatts = nil
            missingKeys.append("gpu_power")
        }

        let aneWatts: Double?
        if let v = processor["ane_power"] as? NSNumber {
            aneWatts = v.doubleValue / 1000.0
        } else {
            aneWatts = nil
            missingKeys.append("ane_power")
        }

        if sampleDurationSec == nil {
            missingKeys.append("elapsed_ns")
        }

        if !missingKeys.isEmpty {
            parserStatus = "partial"
        }

        return ParseResult(
            hardwareFamily: .appleSilicon,
            sourceLevel: "A",
            parserStatus: parserStatus,
            avgWatts: avgWatts,
            cpuWatts: cpuWatts,
            gpuWatts: gpuWatts,
            aneWatts: aneWatts,
            sampleDurationSec: sampleDurationSec,
            missingKeys: missingKeys
        )
    }

    // MARK: - Intel

    /// Intel の plist をパースする (7.2.2)
    public func parseIntel(_ sample: [String: Any]) -> ParseResult {
        guard let processor = sample["processor"] as? [String: Any] else {
            return failResult(message: "No 'processor' key")
        }
        let packagePower = (processor["package_power"] as? NSNumber)?.doubleValue
        let sampleDurationSec: Double?
        if let elapsedNs = sample["elapsed_ns"] as? NSNumber {
            sampleDurationSec = elapsedNs.doubleValue / 1_000_000_000.0
        } else {
            sampleDurationSec = nil
        }

        if let w = packagePower {
            return parseIntelFromValues(packagePowerW: w, sampleDurationSec: sampleDurationSec)
        }
        return ParseResult(
            hardwareFamily: .intel,
            sourceLevel: "C",
            parserStatus: "fail",
            avgWatts: nil,
            cpuWatts: nil,
            gpuWatts: nil,
            aneWatts: nil,
            sampleDurationSec: sampleDurationSec,
            missingKeys: ["package_power"]
        )
    }

    private func parseIntelFromValues(packagePowerW: Double, sampleDurationSec: Double?) -> ParseResult {
        var missingKeys: [String] = []
        if sampleDurationSec == nil {
            missingKeys.append("elapsed_ns")
        }

        return ParseResult(
            hardwareFamily: .intel,
            sourceLevel: "A",
            parserStatus: missingKeys.isEmpty ? "success" : "partial",
            avgWatts: packagePowerW,
            cpuWatts: nil,
            gpuWatts: nil,
            aneWatts: nil,
            sampleDurationSec: sampleDurationSec,
            missingKeys: missingKeys
        )
    }

    private func failResult(message: String) -> ParseResult {
        return ParseResult(
            hardwareFamily: .unknown,
            sourceLevel: "C",
            parserStatus: "fail",
            avgWatts: nil,
            cpuWatts: nil,
            gpuWatts: nil,
            aneWatts: nil,
            sampleDurationSec: nil,
            missingKeys: []
        )
    }

    // MARK: - Types

    /// パース結果
    public struct ParseResult: Sendable {
        public let hardwareFamily: HardwareFamily
        public let sourceLevel: String
        public let parserStatus: String
        public let avgWatts: Double?
        public let cpuWatts: Double?
        public let gpuWatts: Double?
        public let aneWatts: Double?
        public let sampleDurationSec: Double?
        public let missingKeys: [String]

        public init(hardwareFamily: HardwareFamily, sourceLevel: String, parserStatus: String, avgWatts: Double?, cpuWatts: Double?, gpuWatts: Double?, aneWatts: Double?, sampleDurationSec: Double?, missingKeys: [String]) {
            self.hardwareFamily = hardwareFamily
            self.sourceLevel = sourceLevel
            self.parserStatus = parserStatus
            self.avgWatts = avgWatts
            self.cpuWatts = cpuWatts
            self.gpuWatts = gpuWatts
            self.aneWatts = aneWatts
            self.sampleDurationSec = sampleDurationSec
            self.missingKeys = missingKeys
        }
    }

    /// ハードウェアファミリ
    public enum HardwareFamily: String, Sendable, Equatable {
        case appleSilicon = "apple_silicon"
        case intel = "intel"
        case unknown = "unknown"
    }

    public init() {}
}
