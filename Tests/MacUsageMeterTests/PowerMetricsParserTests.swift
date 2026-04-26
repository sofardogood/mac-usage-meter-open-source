import XCTest
@testable import MacUsageMeter
import Shared

/// PowerMetricsParser の単体テスト (第16.1節)
///
/// 観点: plist パース、Apple Silicon / Intel 差分、キー欠損時の partial 判定、mW→W 変換
final class PowerMetricsParserTests: XCTestCase {

    var parser: PowerMetricsParser!

    override func setUp() {
        super.setUp()
        parser = PowerMetricsParser()
    }

    // MARK: - Apple Silicon

    /// Apple Silicon: combined_power が正常に取得できる場合
    /// source_level=A, parserStatus=success, avgWatts = combined_power / 1000.0
    func test_appleSilicon_fullPlist_successParseWithAllKeys() {
        let plist = appleSiliconFullPlist(
            combinedPower: 25000,  // 25000 mW = 25.0 W
            cpuPower: 15000,       // 15.0 W
            gpuPower: 8000,        // 8.0 W
            anePower: 2000,        // 2.0 W
            elapsedNs: 1_000_000_000  // 1 sec
        )

        let result = parser.parse(plist)

        XCTAssertEqual(result.hardwareFamily, .appleSilicon)
        XCTAssertEqual(result.sourceLevel, "A")
        XCTAssertEqual(result.parserStatus, "success")
        XCTAssertEqual(result.avgWatts!, 25.0, accuracy: 0.001)
        XCTAssertEqual(result.cpuWatts!, 15.0, accuracy: 0.001)
        XCTAssertEqual(result.gpuWatts!, 8.0, accuracy: 0.001)
        XCTAssertEqual(result.aneWatts!, 2.0, accuracy: 0.001)
        XCTAssertEqual(result.sampleDurationSec!, 1.0, accuracy: 0.001)
        XCTAssertTrue(result.missingKeys.isEmpty)
    }

    /// Apple Silicon: combined_power あり、gpu_power なし → partial
    /// source_level=A, parserStatus=partial, avgWatts は取得可能
    func test_appleSilicon_missingGpuPower_partialStatus() {
        let plist = appleSiliconPlistMissingGpu(
            combinedPower: 20000,
            cpuPower: 12000,
            elapsedNs: 2_000_000_000
        )

        let result = parser.parse(plist)

        XCTAssertEqual(result.hardwareFamily, .appleSilicon)
        XCTAssertEqual(result.sourceLevel, "A")
        XCTAssertEqual(result.parserStatus, "partial")
        XCTAssertEqual(result.avgWatts!, 20.0, accuracy: 0.001)
        XCTAssertEqual(result.cpuWatts!, 12.0, accuracy: 0.001)
        XCTAssertNil(result.gpuWatts)
        XCTAssertTrue(result.missingKeys.contains("gpu_power"))
    }

    /// Apple Silicon: mW → W 変換の精度確認
    /// 15000 mW → 15.0 W
    func test_appleSilicon_milliwattConversion_correctWattValue() {
        let plist = appleSiliconFullPlist(
            combinedPower: 15000,
            cpuPower: 10000,
            gpuPower: 3500,
            anePower: 1500,
            elapsedNs: 1_000_000_000
        )

        let result = parser.parse(plist)

        XCTAssertEqual(result.avgWatts!, 15.0, accuracy: 0.0001)
        XCTAssertEqual(result.cpuWatts!, 10.0, accuracy: 0.0001)
        XCTAssertEqual(result.gpuWatts!, 3.5, accuracy: 0.0001)
        XCTAssertEqual(result.aneWatts!, 1.5, accuracy: 0.0001)
    }

    /// Apple Silicon: combined_power 欠損で cpu_power フォールバック → source_level=B
    func test_appleSilicon_missingCombinedPower_fallbackToCpuPowerSourceLevelB() {
        let plist = appleSiliconCpuOnlyPlist(
            cpuPower: 12000,
            elapsedNs: 1_000_000_000
        )

        let result = parser.parse(plist)

        XCTAssertEqual(result.sourceLevel, "B")
        // cpu_power のみの場合、avgWatts は nil で cpuWatts にフォールバック
        XCTAssertNil(result.avgWatts)
        XCTAssertEqual(result.cpuWatts!, 12.0, accuracy: 0.001)
    }

    // MARK: - Intel

    /// Intel: package_power が正常に取得できる場合
    /// source_level=A, parserStatus=success, 単位は W (変換不要)
    func test_intel_fullPlist_successParseNoConversion() {
        let plist = intelFullPlist(
            packagePower: 45.5,
            elapsedNs: 1_000_000_000
        )

        let result = parser.parse(plist)

        XCTAssertEqual(result.hardwareFamily, .intel)
        XCTAssertEqual(result.sourceLevel, "A")
        XCTAssertEqual(result.parserStatus, "success")
        XCTAssertEqual(result.avgWatts!, 45.5, accuracy: 0.001)
        XCTAssertEqual(result.sampleDurationSec!, 1.0, accuracy: 0.001)
    }

    /// Intel: package_power が存在しない場合 → source_level=C
    func test_intel_missingPackagePower_sourceLevelC() {
        let plist = intelPlistMissingPackagePower(elapsedNs: 1_000_000_000)

        let result = parser.parse(plist)

        XCTAssertEqual(result.sourceLevel, "C")
        XCTAssertEqual(result.parserStatus, "fail")
        XCTAssertNil(result.avgWatts)
    }

    // MARK: - Edge Cases

    /// processor ディクショナリ自体が存在しない場合 → source_level=C, fail
    func test_parse_missingProcessorDict_sourceLevelCFail() {
        let plist = plistWithoutProcessor(elapsedNs: 1_000_000_000)

        let result = parser.parse(plist)

        XCTAssertEqual(result.sourceLevel, "C")
        XCTAssertEqual(result.parserStatus, "fail")
        XCTAssertNil(result.avgWatts)
        XCTAssertEqual(result.hardwareFamily, .unknown)
    }

    /// 空の plist データ → fail
    func test_parse_emptyInput_failResult() {
        let result = parser.parse("")

        XCTAssertEqual(result.parserStatus, "fail")
        XCTAssertEqual(result.sourceLevel, "C")
        XCTAssertNil(result.avgWatts)
        XCTAssertNil(result.sampleDurationSec)
    }

    /// elapsed_ns が存在しない場合 → sample_duration_sec = nil
    func test_parse_missingElapsedNs_sampleDurationNil() {
        let plist = appleSiliconPlistMissingElapsed(combinedPower: 20000)

        let result = parser.parse(plist)

        XCTAssertNil(result.sampleDurationSec)
        // avgWatts は取得できる
        XCTAssertEqual(result.avgWatts!, 20.0, accuracy: 0.001)
    }

    /// パース優先順位: combined_power が存在すれば Apple Silicon として処理
    func test_parse_bothCombinedAndPackage_appleSiliconPriority() {
        // combined_power と package_power の両方がある場合
        let plist = plistWithBothCombinedAndPackage(
            combinedPower: 25000,
            packagePower: 50.0,
            elapsedNs: 1_000_000_000
        )

        let result = parser.parse(plist)

        XCTAssertEqual(result.hardwareFamily, .appleSilicon)
        XCTAssertEqual(result.avgWatts!, 25.0, accuracy: 0.001)
    }

    /// パース優先順位: combined_power なし + package_power あり → Intel
    func test_parse_onlyPackagePower_intelDetected() {
        let plist = intelFullPlist(packagePower: 55.0, elapsedNs: 1_000_000_000)

        let result = parser.parse(plist)

        XCTAssertEqual(result.hardwareFamily, .intel)
        XCTAssertEqual(result.avgWatts!, 55.0, accuracy: 0.001)
    }

    /// source_level 判定: A (combined_power or package_power 取得可能)
    func test_sourceLevel_combinedPowerAvailable_levelA() {
        let plist = appleSiliconFullPlist(
            combinedPower: 30000, cpuPower: 20000,
            gpuPower: 8000, anePower: 2000, elapsedNs: 1_000_000_000
        )
        let result = parser.parse(plist)
        XCTAssertEqual(result.sourceLevel, "A")
    }

    /// source_level 判定: C (いずれも取得不可)
    func test_sourceLevel_noMetrics_levelC() {
        let plist = plistWithEmptyProcessor(elapsedNs: 1_000_000_000)
        let result = parser.parse(plist)
        XCTAssertEqual(result.sourceLevel, "C")
    }

    // MARK: - Test Helpers: plist construction

    /// Apple Silicon フル plist を生成する (全キーあり)
    private func appleSiliconFullPlist(
        combinedPower: Int,
        cpuPower: Int,
        gpuPower: Int,
        anePower: Int,
        elapsedNs: Int64
    ) -> String {
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <array>
            <dict>
                <key>elapsed_ns</key>
                <integer>\(elapsedNs)</integer>
                <key>processor</key>
                <dict>
                    <key>combined_power</key>
                    <integer>\(combinedPower)</integer>
                    <key>cpu_power</key>
                    <integer>\(cpuPower)</integer>
                    <key>gpu_power</key>
                    <integer>\(gpuPower)</integer>
                    <key>ane_power</key>
                    <integer>\(anePower)</integer>
                </dict>
            </dict>
        </array>
        </plist>
        """
    }

    /// Apple Silicon plist: gpu_power 欠損
    private func appleSiliconPlistMissingGpu(
        combinedPower: Int,
        cpuPower: Int,
        elapsedNs: Int64
    ) -> String {
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <array>
            <dict>
                <key>elapsed_ns</key>
                <integer>\(elapsedNs)</integer>
                <key>processor</key>
                <dict>
                    <key>combined_power</key>
                    <integer>\(combinedPower)</integer>
                    <key>cpu_power</key>
                    <integer>\(cpuPower)</integer>
                </dict>
            </dict>
        </array>
        </plist>
        """
    }

    /// Apple Silicon plist: combined_power 欠損、cpu_power のみ → source_level=B
    private func appleSiliconCpuOnlyPlist(cpuPower: Int, elapsedNs: Int64) -> String {
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <array>
            <dict>
                <key>elapsed_ns</key>
                <integer>\(elapsedNs)</integer>
                <key>processor</key>
                <dict>
                    <key>cpu_power</key>
                    <integer>\(cpuPower)</integer>
                </dict>
            </dict>
        </array>
        </plist>
        """
    }

    /// Apple Silicon plist: elapsed_ns 欠損
    private func appleSiliconPlistMissingElapsed(combinedPower: Int) -> String {
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <array>
            <dict>
                <key>processor</key>
                <dict>
                    <key>combined_power</key>
                    <integer>\(combinedPower)</integer>
                </dict>
            </dict>
        </array>
        </plist>
        """
    }

    /// Intel フル plist
    private func intelFullPlist(packagePower: Double, elapsedNs: Int64) -> String {
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <array>
            <dict>
                <key>elapsed_ns</key>
                <integer>\(elapsedNs)</integer>
                <key>processor</key>
                <dict>
                    <key>package_power</key>
                    <real>\(packagePower)</real>
                </dict>
            </dict>
        </array>
        </plist>
        """
    }

    /// Intel plist: package_power 欠損
    private func intelPlistMissingPackagePower(elapsedNs: Int64) -> String {
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <array>
            <dict>
                <key>elapsed_ns</key>
                <integer>\(elapsedNs)</integer>
                <key>processor</key>
                <dict>
                </dict>
            </dict>
        </array>
        </plist>
        """
    }

    /// processor ディクショナリなし
    private func plistWithoutProcessor(elapsedNs: Int64) -> String {
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <array>
            <dict>
                <key>elapsed_ns</key>
                <integer>\(elapsedNs)</integer>
            </dict>
        </array>
        </plist>
        """
    }

    /// processor ディクショナリ空
    private func plistWithEmptyProcessor(elapsedNs: Int64) -> String {
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <array>
            <dict>
                <key>elapsed_ns</key>
                <integer>\(elapsedNs)</integer>
                <key>processor</key>
                <dict>
                </dict>
            </dict>
        </array>
        </plist>
        """
    }

    /// combined_power と package_power の両方があるケース
    private func plistWithBothCombinedAndPackage(
        combinedPower: Int,
        packagePower: Double,
        elapsedNs: Int64
    ) -> String {
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <array>
            <dict>
                <key>elapsed_ns</key>
                <integer>\(elapsedNs)</integer>
                <key>processor</key>
                <dict>
                    <key>combined_power</key>
                    <integer>\(combinedPower)</integer>
                    <key>package_power</key>
                    <real>\(packagePower)</real>
                </dict>
            </dict>
        </array>
        </plist>
        """
    }
}
