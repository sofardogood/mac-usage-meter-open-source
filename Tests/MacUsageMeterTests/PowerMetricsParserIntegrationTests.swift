import XCTest
@testable import MacUsageMeter
import Shared

/// PowerMetricsParser フィクスチャベース統合テスト
///
/// 実機の powermetrics plist 出力を模擬したフィクスチャファイルを読み込み、
/// パーサーの正確性を端から端まで検証する。
final class PowerMetricsParserIntegrationTests: XCTestCase {

    var parser: PowerMetricsParser!

    override func setUp() {
        super.setUp()
        parser = PowerMetricsParser()
    }

    // MARK: - Fixture Loading

    /// フィクスチャファイルを文字列として読み込む
    private func loadFixture(_ name: String) throws -> String {
        // Bundle.module はリソースバンドルが設定されている場合に利用可能
        // フォールバック: ソースツリーからの相対パスで読み込む
        let fixtureDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
        let fileURL = fixtureDir.appendingPathComponent(name)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    // MARK: - Apple Silicon M4 Full

    /// M4 Pro フル出力: 全キーが存在し、source_level=A, parserStatus=success
    func test_appleSiliconM4Full_allKeysPresent_sourceLevelA() throws {
        let plist = try loadFixture("apple_silicon_m4_full.plist")
        let result = parser.parse(plist)

        XCTAssertEqual(result.hardwareFamily, .appleSilicon,
                       "M4 Pro は Apple Silicon として検出されること")
        XCTAssertEqual(result.sourceLevel, "A",
                       "全キー存在時は source_level=A")
        XCTAssertEqual(result.parserStatus, "success",
                       "全キー存在時は parserStatus=success")
    }

    /// M4 Pro フル出力: combined_power の mW→W 変換
    func test_appleSiliconM4Full_combinedPower_milliwattToWattConversion() throws {
        let plist = try loadFixture("apple_silicon_m4_full.plist")
        let result = parser.parse(plist)

        // 8500 mW → 8.5 W
        XCTAssertNotNil(result.avgWatts)
        XCTAssertEqual(result.avgWatts!, 8.5, accuracy: 0.001,
                       "combined_power 8500 mW → 8.5 W")
    }

    /// M4 Pro フル出力: cpu_power の mW→W 変換
    func test_appleSiliconM4Full_cpuPower_milliwattToWattConversion() throws {
        let plist = try loadFixture("apple_silicon_m4_full.plist")
        let result = parser.parse(plist)

        // 5200 mW → 5.2 W
        XCTAssertNotNil(result.cpuWatts)
        XCTAssertEqual(result.cpuWatts!, 5.2, accuracy: 0.001,
                       "cpu_power 5200 mW → 5.2 W")
    }

    /// M4 Pro フル出力: gpu_power の mW→W 変換
    func test_appleSiliconM4Full_gpuPower_milliwattToWattConversion() throws {
        let plist = try loadFixture("apple_silicon_m4_full.plist")
        let result = parser.parse(plist)

        // 2100 mW → 2.1 W
        XCTAssertNotNil(result.gpuWatts)
        XCTAssertEqual(result.gpuWatts!, 2.1, accuracy: 0.001,
                       "gpu_power 2100 mW → 2.1 W")
    }

    /// M4 Pro フル出力: ane_power の mW→W 変換
    func test_appleSiliconM4Full_anePower_milliwattToWattConversion() throws {
        let plist = try loadFixture("apple_silicon_m4_full.plist")
        let result = parser.parse(plist)

        // 1200 mW → 1.2 W
        XCTAssertNotNil(result.aneWatts)
        XCTAssertEqual(result.aneWatts!, 1.2, accuracy: 0.001,
                       "ane_power 1200 mW → 1.2 W")
    }

    /// M4 Pro フル出力: elapsed_ns → sampleDurationSec 変換
    func test_appleSiliconM4Full_elapsedNs_toSeconds() throws {
        let plist = try loadFixture("apple_silicon_m4_full.plist")
        let result = parser.parse(plist)

        // 1000000000 ns → 1.0 sec
        XCTAssertNotNil(result.sampleDurationSec)
        XCTAssertEqual(result.sampleDurationSec!, 1.0, accuracy: 0.001,
                       "elapsed_ns 1000000000 → 1.0 sec")
    }

    /// M4 Pro フル出力: missingKeys は空
    func test_appleSiliconM4Full_noMissingKeys() throws {
        let plist = try loadFixture("apple_silicon_m4_full.plist")
        let result = parser.parse(plist)

        XCTAssertTrue(result.missingKeys.isEmpty,
                      "全キーが存在するフィクスチャでは missingKeys が空であること")
    }

    /// M4 Pro フル出力: 値の妥当な範囲チェック (アイドル~軽負荷)
    func test_appleSiliconM4Full_valuesInRealisticRange() throws {
        let plist = try loadFixture("apple_silicon_m4_full.plist")
        let result = parser.parse(plist)

        // M4 Pro のアイドル~軽負荷時の現実的な範囲
        XCTAssertGreaterThan(result.avgWatts!, 0.0, "電力は正の値")
        XCTAssertLessThan(result.avgWatts!, 100.0, "Apple Silicon では 100W 未満")

        XCTAssertGreaterThan(result.cpuWatts!, 0.0)
        XCTAssertLessThan(result.cpuWatts!, 50.0)

        XCTAssertGreaterThan(result.gpuWatts!, 0.0)
        XCTAssertLessThan(result.gpuWatts!, 50.0)

        XCTAssertGreaterThanOrEqual(result.aneWatts!, 0.0)
        XCTAssertLessThan(result.aneWatts!, 20.0)
    }

    /// M4 Pro フル出力: パーサーが unknown キー (hw_model, clusters 等) を無視する
    func test_appleSiliconM4Full_unknownKeysIgnored() throws {
        let plist = try loadFixture("apple_silicon_m4_full.plist")
        let result = parser.parse(plist)

        // hw_model, kern_osversion, clusters 等の追加キーがあってもパースが成功すること
        XCTAssertEqual(result.parserStatus, "success",
                       "パーサーは想定外のキーを無視して正常にパースを完了すること")
        XCTAssertEqual(result.hardwareFamily, .appleSilicon)
    }

    // MARK: - Apple Silicon Partial (combined_power 欠損)

    /// Partial フィクスチャ: combined_power 欠損で source_level=B
    func test_appleSiliconPartial_noCombinedPower_sourceLevelB() throws {
        let plist = try loadFixture("apple_silicon_partial.plist")
        let result = parser.parse(plist)

        XCTAssertEqual(result.sourceLevel, "B",
                       "combined_power 欠損時は source_level=B (cpu_power フォールバック)")
        XCTAssertEqual(result.parserStatus, "partial")
    }

    /// Partial フィクスチャ: avgWatts は nil、cpuWatts のみ取得可能
    func test_appleSiliconPartial_avgWattsNil_cpuWattsAvailable() throws {
        let plist = try loadFixture("apple_silicon_partial.plist")
        let result = parser.parse(plist)

        XCTAssertNil(result.avgWatts,
                     "combined_power なしでは avgWatts は nil")
        XCTAssertNotNil(result.cpuWatts)
        // 5200 mW → 5.2 W
        XCTAssertEqual(result.cpuWatts!, 5.2, accuracy: 0.001)
    }

    /// Partial フィクスチャ: missingKeys に combined_power が含まれる
    func test_appleSiliconPartial_missingKeysContainsCombinedPower() throws {
        let plist = try loadFixture("apple_silicon_partial.plist")
        let result = parser.parse(plist)

        XCTAssertTrue(result.missingKeys.contains("combined_power"),
                      "missingKeys に combined_power が含まれること")
        XCTAssertTrue(result.missingKeys.contains("package_power"),
                      "missingKeys に package_power が含まれること")
    }

    /// Partial フィクスチャ: パーサーが unknown キー (clusters 等) を無視する
    func test_appleSiliconPartial_unknownKeysIgnored() throws {
        let plist = try loadFixture("apple_silicon_partial.plist")
        let result = parser.parse(plist)

        // clusters, cpu_energy 等があってもパースが継続すること
        XCTAssertNotEqual(result.parserStatus, "fail",
                          "追加キーが存在してもパース失敗にならないこと")
    }

    // MARK: - Intel Full

    /// Intel フル出力: package_power 存在で source_level=A
    func test_intelFull_packagePowerPresent_sourceLevelA() throws {
        let plist = try loadFixture("intel_full.plist")
        let result = parser.parse(plist)

        XCTAssertEqual(result.hardwareFamily, .intel,
                       "Intel Mac として検出されること")
        XCTAssertEqual(result.sourceLevel, "A")
        XCTAssertEqual(result.parserStatus, "success")
    }

    /// Intel フル出力: package_power は W 単位 (変換不要)
    func test_intelFull_packagePower_wattsNoConversion() throws {
        let plist = try loadFixture("intel_full.plist")
        let result = parser.parse(plist)

        // Intel では package_power は W 単位 → そのまま avgWatts に
        XCTAssertNotNil(result.avgWatts)
        XCTAssertEqual(result.avgWatts!, 35.5, accuracy: 0.001,
                       "Intel の package_power 35.5 W はそのまま avgWatts に格納")
    }

    /// Intel フル出力: elapsed_ns → sampleDurationSec 変換
    func test_intelFull_elapsedNs_toSeconds() throws {
        let plist = try loadFixture("intel_full.plist")
        let result = parser.parse(plist)

        XCTAssertNotNil(result.sampleDurationSec)
        XCTAssertEqual(result.sampleDurationSec!, 1.0, accuracy: 0.001)
    }

    /// Intel フル出力: Apple Silicon 固有キーは nil
    func test_intelFull_appleSiliconKeysNil() throws {
        let plist = try loadFixture("intel_full.plist")
        let result = parser.parse(plist)

        XCTAssertNil(result.cpuWatts, "Intel では cpuWatts は nil")
        XCTAssertNil(result.gpuWatts, "Intel では gpuWatts は nil")
        XCTAssertNil(result.aneWatts, "Intel では aneWatts は nil")
    }

    /// Intel フル出力: 値の妥当な範囲チェック
    func test_intelFull_valuesInRealisticRange() throws {
        let plist = try loadFixture("intel_full.plist")
        let result = parser.parse(plist)

        // Intel ラップトップの一般的な範囲
        XCTAssertGreaterThan(result.avgWatts!, 0.0, "電力は正の値")
        XCTAssertLessThan(result.avgWatts!, 200.0, "Intel ラップトップでは 200W 未満")
    }

    /// Intel フル出力: パーサーが unknown キー (packages, cores 等) を無視する
    func test_intelFull_unknownKeysIgnored() throws {
        let plist = try loadFixture("intel_full.plist")
        let result = parser.parse(plist)

        // packages, cores, cstate_residency 等があってもパースが成功すること
        XCTAssertEqual(result.parserStatus, "success",
                       "パーサーは想定外のキーを無視して正常にパースを完了すること")
    }

    // MARK: - Empty Processor (source_level=C)

    /// Empty processor: processor ディクショナリが空 → source_level=C
    func test_emptyProcessor_sourceLevelC() throws {
        let plist = try loadFixture("empty_processor.plist")
        let result = parser.parse(plist)

        XCTAssertEqual(result.sourceLevel, "C",
                       "processor が空の場合は source_level=C")
        XCTAssertEqual(result.parserStatus, "fail")
    }

    /// Empty processor: 全メトリクスが nil
    func test_emptyProcessor_allMetricsNil() throws {
        let plist = try loadFixture("empty_processor.plist")
        let result = parser.parse(plist)

        XCTAssertNil(result.avgWatts)
        XCTAssertNil(result.cpuWatts)
        XCTAssertNil(result.gpuWatts)
        XCTAssertNil(result.aneWatts)
    }

    /// Empty processor: hardwareFamily は unknown
    func test_emptyProcessor_hardwareFamilyUnknown() throws {
        let plist = try loadFixture("empty_processor.plist")
        let result = parser.parse(plist)

        XCTAssertEqual(result.hardwareFamily, .unknown)
    }

    /// Empty processor: missingKeys に主要キーが列挙される
    func test_emptyProcessor_missingKeysListsAllPrimaryKeys() throws {
        let plist = try loadFixture("empty_processor.plist")
        let result = parser.parse(plist)

        XCTAssertTrue(result.missingKeys.contains("combined_power"),
                      "missingKeys に combined_power が含まれること")
        XCTAssertTrue(result.missingKeys.contains("package_power"),
                      "missingKeys に package_power が含まれること")
        XCTAssertTrue(result.missingKeys.contains("cpu_power"),
                      "missingKeys に cpu_power が含まれること")
    }

    // MARK: - Cross-Fixture Key Path Consistency

    /// 全フィクスチャの sampleDurationSec が一貫して 1.0 秒であること
    func test_allFixtures_consistentSampleDuration() throws {
        let fixtures = [
            "apple_silicon_m4_full.plist",
            "apple_silicon_partial.plist",
            "intel_full.plist",
            "empty_processor.plist"
        ]

        for fixture in fixtures {
            let plist = try loadFixture(fixture)
            let result = parser.parse(plist)
            XCTAssertNotNil(result.sampleDurationSec,
                            "\(fixture): sampleDurationSec が取得できること")
            XCTAssertEqual(result.sampleDurationSec!, 1.0, accuracy: 0.001,
                           "\(fixture): sampleDurationSec が 1.0 秒であること")
        }
    }

    /// キーパス検証: 全フィクスチャで processor キーパスが正しく解釈される
    func test_allFixtures_processorKeyPathResolved() throws {
        let fixtures = [
            "apple_silicon_m4_full.plist",
            "apple_silicon_partial.plist",
            "intel_full.plist",
            "empty_processor.plist"
        ]

        for fixture in fixtures {
            let plist = try loadFixture(fixture)
            let result = parser.parse(plist)
            // source_level=C の fail でも、processor キーが存在する限り
            // "No 'processor' key in sample" エラーにはならない
            // (empty_processor は processor dict が空なので fail だが processor 自体は存在)
            XCTAssertNotEqual(result.parserStatus, "fail_no_processor",
                              "\(fixture): processor キーパスが解決されること")
        }
    }
}
