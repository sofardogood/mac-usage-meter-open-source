import Foundation
import Shared

/// 能力検出 (第7.3節)
///
/// 起動時と OS バージョン変更検知時に powermetrics を単発実行し、
/// 利用可能なキーの有無で source_level を判定する。
/// 検出結果は構造化ログとして出力し、JSON ファイルに永続化する。
struct CapabilityProbe: Sendable {

    /// powermetrics 実行器
    private let executor = PowerMetricsExecutor()

    /// powermetrics パーサー
    private let parser = PowerMetricsParser()

    /// パーサーが想定する Apple Silicon キー一覧
    static let expectedAppleSiliconKeys = [
        "combined_power", "cpu_power", "gpu_power", "ane_power"
    ]

    /// パーサーが想定する Intel キー一覧
    static let expectedIntelKeys = [
        "package_power"
    ]

    /// 共通の想定キー (トップレベル)
    static let expectedTopLevelKeys = [
        "elapsed_ns", "processor"
    ]

    // MARK: - Probe

    /// 能力検出を実行する
    ///
    /// `/usr/bin/powermetrics --sample-count 1 -f plist --samplers cpu_power` を1回実行し、
    /// 結果をパースして利用可能プロファイルを返す。
    /// 実際に取得できたキー一覧を構造化ログに出力し、JSON ファイルに保存する。
    ///
    /// - Returns: 検出結果
    func probe() -> ProbeResult {
        let osMajorVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        let probeTimestamp = ISO8601DateFormatter().string(from: Date())

        do {
            let result = try executor.executeProbe()

            if result.exitCode != 0 {
                // powermetrics 実行失敗 → source_level C
                let probeResult = ProbeResult(
                    hardwareFamily: .unknown,
                    osMajorVersion: osMajorVersion,
                    profiles: []
                )
                let report = buildProbeReport(
                    probeResult: probeResult,
                    detectedKeys: [],
                    missingKeys: [],
                    unexpectedKeys: [],
                    rawPlistAvailable: false,
                    exitCode: result.exitCode,
                    errorMessage: "powermetrics exited with code \(result.exitCode): \(result.stderr)",
                    timestamp: probeTimestamp
                )
                logProbeReport(report)
                saveProbeReport(report)
                return probeResult
            }

            let parseResult = parser.parse(result.stdout)

            // 実際に取得できたキーを plist から抽出
            let detectedKeys = extractDetectedKeys(from: result.stdout)

            // パーサーが想定するキーと実際のキーの差分を検出
            let expectedKeys: [String]
            switch parseResult.hardwareFamily {
            case .appleSilicon:
                expectedKeys = Self.expectedTopLevelKeys + Self.expectedAppleSiliconKeys
            case .intel:
                expectedKeys = Self.expectedTopLevelKeys + Self.expectedIntelKeys
            case .unknown:
                expectedKeys = Self.expectedTopLevelKeys + Self.expectedAppleSiliconKeys + Self.expectedIntelKeys
            }

            let missingKeys = expectedKeys.filter { !detectedKeys.contains($0) }
            let knownKeys = Set(Self.expectedTopLevelKeys + Self.expectedAppleSiliconKeys + Self.expectedIntelKeys)
            let unexpectedKeys = detectedKeys.filter { !knownKeys.contains($0) }

            // プロファイル構築
            var profiles: [Profile] = []

            switch parseResult.sourceLevel {
            case "A":
                let profileExpectedKeys: [String]
                if parseResult.hardwareFamily == .appleSilicon {
                    profileExpectedKeys = ["combined_power", "cpu_power", "gpu_power", "ane_power", "elapsed_ns"]
                } else {
                    profileExpectedKeys = ["package_power", "elapsed_ns"]
                }
                profiles.append(Profile(
                    profileId: "default_\(parseResult.hardwareFamily.rawValue)",
                    sourceLevel: "A",
                    expectedMetricKeys: profileExpectedKeys
                ))
            case "B":
                profiles.append(Profile(
                    profileId: "partial_cpu_only",
                    sourceLevel: "B",
                    expectedMetricKeys: ["cpu_power", "elapsed_ns"]
                ))
            default:
                // source_level C → profiles 空
                break
            }

            let probeResult = ProbeResult(
                hardwareFamily: parseResult.hardwareFamily,
                osMajorVersion: osMajorVersion,
                profiles: profiles
            )

            let report = buildProbeReport(
                probeResult: probeResult,
                detectedKeys: detectedKeys,
                missingKeys: missingKeys,
                unexpectedKeys: unexpectedKeys,
                rawPlistAvailable: true,
                exitCode: result.exitCode,
                errorMessage: nil,
                timestamp: probeTimestamp
            )
            logProbeReport(report)
            saveProbeReport(report)

            return probeResult

        } catch {
            // 実行自体が失敗 → source_level C
            let probeResult = ProbeResult(
                hardwareFamily: .unknown,
                osMajorVersion: osMajorVersion,
                profiles: []
            )
            let report = buildProbeReport(
                probeResult: probeResult,
                detectedKeys: [],
                missingKeys: [],
                unexpectedKeys: [],
                rawPlistAvailable: false,
                exitCode: nil,
                errorMessage: error.localizedDescription,
                timestamp: probeTimestamp
            )
            logProbeReport(report)
            saveProbeReport(report)
            return probeResult
        }
    }

    // MARK: - Key Extraction

    /// plist 出力から processor ディクショナリ内の実際のキー一覧を抽出する
    private func extractDetectedKeys(from plistString: String) -> [String] {
        guard let data = plistString.data(using: .utf8) else { return [] }

        let plistObj: Any
        do {
            plistObj = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            return []
        }

        var keys: [String] = []

        let sample: [String: Any]
        if let array = plistObj as? [[String: Any]], let last = array.last {
            sample = last
        } else if let dict = plistObj as? [String: Any] {
            sample = dict
        } else {
            return []
        }

        // トップレベルキー (パーサーが参照するもの)
        if sample["elapsed_ns"] != nil {
            keys.append("elapsed_ns")
        }
        if sample["processor"] != nil {
            keys.append("processor")
        }

        // processor 内のキー
        if let processor = sample["processor"] as? [String: Any] {
            for key in processor.keys.sorted() {
                keys.append(key)
            }
        }

        return keys
    }

    // MARK: - Probe Report

    /// probe レポートを構築する
    private func buildProbeReport(
        probeResult: ProbeResult,
        detectedKeys: [String],
        missingKeys: [String],
        unexpectedKeys: [String],
        rawPlistAvailable: Bool,
        exitCode: Int32?,
        errorMessage: String?,
        timestamp: String
    ) -> ProbeReport {
        return ProbeReport(
            timestamp: timestamp,
            osMajorVersion: probeResult.osMajorVersion,
            hardwareFamily: probeResult.hardwareFamily.rawValue,
            bestSourceLevel: probeResult.bestSourceLevel,
            profileCount: probeResult.profiles.count,
            profiles: probeResult.profiles.map {
                ProbeReport.ProfileEntry(
                    profileId: $0.profileId,
                    sourceLevel: $0.sourceLevel,
                    expectedMetricKeys: $0.expectedMetricKeys
                )
            },
            detectedKeys: detectedKeys,
            missingKeys: missingKeys,
            unexpectedKeys: unexpectedKeys,
            rawPlistAvailable: rawPlistAvailable,
            exitCode: exitCode.map { Int($0) },
            errorMessage: errorMessage
        )
    }

    /// 構造化ログとして probe レポートを出力する (os_log スタイル)
    private func logProbeReport(_ report: ProbeReport) {
        // NSLog はフォーマットをサポートし、LaunchDaemon 環境でも確実にログが取れる
        NSLog("[CapabilityProbe] === Probe Report ===")
        NSLog("[CapabilityProbe] timestamp=%@", report.timestamp)
        NSLog("[CapabilityProbe] os_major_version=%d", report.osMajorVersion)
        NSLog("[CapabilityProbe] hardware_family=%@", report.hardwareFamily)
        NSLog("[CapabilityProbe] best_source_level=%@", report.bestSourceLevel)
        NSLog("[CapabilityProbe] profile_count=%d", report.profileCount)

        for profile in report.profiles {
            NSLog("[CapabilityProbe] profile: id=%@ source_level=%@ keys=[%@]",
                  profile.profileId,
                  profile.sourceLevel,
                  profile.expectedMetricKeys.joined(separator: ", "))
        }

        NSLog("[CapabilityProbe] detected_keys=[%@]", report.detectedKeys.joined(separator: ", "))

        if !report.missingKeys.isEmpty {
            NSLog("[CapabilityProbe] WARNING missing_keys=[%@]", report.missingKeys.joined(separator: ", "))
        }

        if !report.unexpectedKeys.isEmpty {
            NSLog("[CapabilityProbe] INFO unexpected_keys=[%@]", report.unexpectedKeys.joined(separator: ", "))
        }

        if let exitCode = report.exitCode {
            NSLog("[CapabilityProbe] exit_code=%d", exitCode)
        }

        if let error = report.errorMessage {
            NSLog("[CapabilityProbe] ERROR %@", error)
        }

        NSLog("[CapabilityProbe] === End Probe Report ===")
    }

    /// probe レポートを JSON ファイルに保存する
    ///
    /// 保存先: ~/Library/Application Support/com.macusagemeter.helper/capability_probe_result.json
    private func saveProbeReport(_ report: ProbeReport) {
        let bundleId = "com.macusagemeter.helper"
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            NSLog("[CapabilityProbe] ERROR: Cannot locate Application Support directory")
            return
        }

        let directoryURL = appSupportURL.appendingPathComponent(bundleId)

        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            NSLog("[CapabilityProbe] ERROR: Cannot create directory %@: %@", directoryURL.path, error.localizedDescription)
            return
        }

        let fileURL = directoryURL.appendingPathComponent("capability_probe_result.json")

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            try data.write(to: fileURL, options: .atomic)
            NSLog("[CapabilityProbe] Probe report saved to %@", fileURL.path)
        } catch {
            NSLog("[CapabilityProbe] ERROR: Cannot save probe report: %@", error.localizedDescription)
        }
    }

    // MARK: - Types

    /// 検出結果
    struct ProbeResult: Sendable {
        let hardwareFamily: PowerMetricsParser.HardwareFamily
        let osMajorVersion: Int
        let profiles: [Profile]

        /// ソースレベル
        var bestSourceLevel: String {
            profiles.first?.sourceLevel ?? "C"
        }
    }

    /// サンプリングプロファイル
    struct Profile: Sendable {
        let profileId: String
        let sourceLevel: String
        let expectedMetricKeys: [String]
    }

    /// probe レポート (JSON 永続化用)
    struct ProbeReport: Codable, Sendable {
        let timestamp: String
        let osMajorVersion: Int
        let hardwareFamily: String
        let bestSourceLevel: String
        let profileCount: Int
        let profiles: [ProfileEntry]
        let detectedKeys: [String]
        let missingKeys: [String]
        let unexpectedKeys: [String]
        let rawPlistAvailable: Bool
        let exitCode: Int?
        let errorMessage: String?

        struct ProfileEntry: Codable, Sendable {
            let profileId: String
            let sourceLevel: String
            let expectedMetricKeys: [String]
        }
    }
}
