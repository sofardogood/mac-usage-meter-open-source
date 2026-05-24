import XCTest
@testable import MacUsageMeter

/// CSV エクスポートの単体テスト (第16.1節)
///
/// 観点: カラム順、UTF-8 BOM、CRLF、欠測値=空文字、ISO 8601 日付
/// 仕様書 付録C に基づく
final class CSVExporterTests: XCTestCase {

    var exporter: CSVExporter!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        exporter = CSVExporter()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CSVExporterTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Format

    /// UTF-8 BOM が先頭3バイトに付与されること (EF BB BF)
    func test_format_utf8BomPresent_first3Bytes() throws {
        let outputURL = tempDir.appendingPathComponent("test_bom.csv")
        let samples = [makePowerSample(avgWatts: 42.0)]

        try exporter.exportRawPower(samples: samples, to: outputURL)

        let data = try Data(contentsOf: outputURL)
        // UTF-8 BOM: EF BB BF
        XCTAssertGreaterThanOrEqual(data.count, 3)
        XCTAssertEqual(data[0], 0xEF)
        XCTAssertEqual(data[1], 0xBB)
        XCTAssertEqual(data[2], 0xBF)
    }

    /// 改行が CRLF であること
    func test_format_crlfLineEndings_present() throws {
        let outputURL = tempDir.appendingPathComponent("test_crlf.csv")
        let samples = [makePowerSample(avgWatts: 42.0)]

        try exporter.exportRawPower(samples: samples, to: outputURL)

        let content = try String(contentsOf: outputURL, encoding: .utf8)
        // BOM を除去してから検証
        let cleanContent = content.replacingOccurrences(of: "\u{FEFF}", with: "")
        // CRLF が含まれること
        XCTAssertTrue(cleanContent.contains("\r\n"), "CSV should use CRLF line endings")
        // LF のみの改行がないこと (全ての \n の前に \r があること)
        let withoutCRLF = cleanContent.replacingOccurrences(of: "\r\n", with: "")
        XCTAssertFalse(withoutCRLF.contains("\n"), "Should not contain bare LF")
    }

    /// ヘッダー行が存在すること
    func test_format_headerRowPresent() throws {
        let outputURL = tempDir.appendingPathComponent("test_header.csv")
        let samples = [makePowerSample(avgWatts: 42.0)]

        try exporter.exportRawPower(samples: samples, to: outputURL)

        let content = try String(contentsOf: outputURL, encoding: .utf8)
        let cleanContent = content.replacingOccurrences(of: "\u{FEFF}", with: "")
        let firstLine = cleanContent.components(separatedBy: "\r\n").first!
        XCTAssertEqual(firstLine, CSVExporter.rawPowerHeader)
    }

    // MARK: - Raw Power

    /// raw_power のカラム順が仕様通りであること
    /// カラム順: captured_at_utc, captured_at_local, avg_watts, sample_duration_sec,
    ///          source_level, status, parser_status, outlier_flag, error_code
    func test_rawPower_columnOrder_matchesSpec() throws {
        let outputURL = tempDir.appendingPathComponent("test_power_cols.csv")
        let sample = makePowerSample(avgWatts: 42.5, sourceLevel: .a, status: .success)

        try exporter.exportRawPower(samples: [sample], to: outputURL)

        let content = try String(contentsOf: outputURL, encoding: .utf8)
        let cleanContent = content.replacingOccurrences(of: "\u{FEFF}", with: "")
        let lines = cleanContent.components(separatedBy: "\r\n").filter { !$0.isEmpty }

        XCTAssertEqual(lines.count, 2, "Should have header + 1 data row")

        let header = lines[0]
        XCTAssertEqual(header, "captured_at_utc,captured_at_local,avg_watts,sample_duration_sec,source_level,status,parser_status,outlier_flag,error_code")

        let dataFields = lines[1].components(separatedBy: ",")
        XCTAssertEqual(dataFields.count, 9, "raw_power should have 9 columns")

        // avg_watts (index 2) should be 42.5
        XCTAssertEqual(dataFields[2], "42.5")
        // source_level (index 4) should be A
        XCTAssertEqual(dataFields[4], "A")
        // status (index 5) should be success
        XCTAssertEqual(dataFields[5], "success")
    }

    /// raw_power: 欠測値 (avg_watts=nil) が空文字であること
    func test_rawPower_missingAvgWatts_emptyString() throws {
        let outputURL = tempDir.appendingPathComponent("test_power_missing.csv")
        let sample = makePowerSample(avgWatts: nil, status: .missing)

        try exporter.exportRawPower(samples: [sample], to: outputURL)

        let content = try String(contentsOf: outputURL, encoding: .utf8)
        let cleanContent = content.replacingOccurrences(of: "\u{FEFF}", with: "")
        let lines = cleanContent.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        let dataFields = lines[1].components(separatedBy: ",")

        // avg_watts (index 2) should be empty for nil value
        XCTAssertEqual(dataFields[2], "", "Missing avg_watts should be empty string, not '0' or 'nil'")
    }

    // MARK: - Raw Wi-Fi

    /// raw_wifi のカラム順が仕様通りであること
    /// カラム順: captured_at_utc, captured_at_local, interface_name, sent_bytes_delta,
    ///          recv_bytes_delta, sent_bytes_total, recv_bytes_total,
    ///          counter_reset_flag, status, error_code
    func test_rawWifi_columnOrder_matchesSpec() throws {
        let outputURL = tempDir.appendingPathComponent("test_wifi_cols.csv")
        let sample = makeWifiSample(sentDelta: 1000, recvDelta: 2000)

        try exporter.exportRawWifi(samples: [sample], to: outputURL)

        let content = try String(contentsOf: outputURL, encoding: .utf8)
        let cleanContent = content.replacingOccurrences(of: "\u{FEFF}", with: "")
        let lines = cleanContent.components(separatedBy: "\r\n").filter { !$0.isEmpty }

        XCTAssertEqual(lines.count, 2)

        let header = lines[0]
        XCTAssertEqual(header, "captured_at_utc,captured_at_local,interface_name,sent_bytes_delta,recv_bytes_delta,sent_bytes_total,recv_bytes_total,counter_reset_flag,status,error_code")

        let dataFields = lines[1].components(separatedBy: ",")
        XCTAssertEqual(dataFields.count, 10, "raw_wifi should have 10 columns")

        // interface_name (index 2)
        XCTAssertEqual(dataFields[2], "en0")
        // sent_bytes_delta (index 3)
        XCTAssertEqual(dataFields[3], "1000")
        // recv_bytes_delta (index 4)
        XCTAssertEqual(dataFields[4], "2000")
    }

    // MARK: - Daily Rollup

    /// daily_rollup のカラム順が仕様通りであること
    /// カラム順: date_local, power_kwh, wifi_gb, power_cost_yen, network_cost_yen,
    ///          coverage_ratio_power, coverage_ratio_wifi,
    ///          sample_count_power, sample_count_wifi, computed_at_utc
    func test_dailyRollup_columnOrder_matchesSpec() throws {
        let outputURL = tempDir.appendingPathComponent("test_rollup_cols.csv")
        let rollup = makeDailyRollup()

        try exporter.exportDailyRollup(rollups: [rollup], to: outputURL)

        let content = try String(contentsOf: outputURL, encoding: .utf8)
        let cleanContent = content.replacingOccurrences(of: "\u{FEFF}", with: "")
        let lines = cleanContent.components(separatedBy: "\r\n").filter { !$0.isEmpty }

        XCTAssertEqual(lines.count, 2)

        let header = lines[0]
        XCTAssertEqual(header, "date_local,power_kwh,wifi_gb,power_cost_yen,network_cost_yen,coverage_ratio_power,coverage_ratio_wifi,sample_count_power,sample_count_wifi,computed_at_utc")

        let dataFields = lines[1].components(separatedBy: ",")
        XCTAssertEqual(dataFields.count, 10, "daily_rollup should have 10 columns")

        // date_local (index 0) should be ISO 8601 date
        XCTAssertEqual(dataFields[0], "2026-03-18")
    }

    /// daily_rollup: 欠測値 (power_kwh=nil) が空文字であること
    func test_dailyRollup_missingPowerKwh_emptyString() throws {
        let outputURL = tempDir.appendingPathComponent("test_rollup_missing.csv")
        let rollup = DailyRollup(
            dateLocal: "2026-03-18",
            powerKwh: nil,
            wifiGb: 1.5,
            powerCostYen: nil,
            networkCostYen: 300.0,
            coverageRatioPower: 0.0,
            coverageRatioWifi: 0.95,
            sampleCountPower: 0,
            sampleCountWifi: 8000,
            computedAtMs: 1742342400000
        )

        try exporter.exportDailyRollup(rollups: [rollup], to: outputURL)

        let content = try String(contentsOf: outputURL, encoding: .utf8)
        let cleanContent = content.replacingOccurrences(of: "\u{FEFF}", with: "")
        let lines = cleanContent.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        let dataFields = lines[1].components(separatedBy: ",")

        // power_kwh (index 1) should be empty for nil
        XCTAssertEqual(dataFields[1], "")
        // power_cost_yen (index 3) should be empty for nil
        XCTAssertEqual(dataFields[3], "")
    }

    // MARK: - Date Format

    /// captured_at_utc: ISO 8601 UTC (yyyy-MM-dd'T'HH:mm:ss'Z')
    func test_dateFormat_utc_iso8601() {
        // 2026-03-18T12:00:00Z = 1774051200000 ms
        let formatted = exporter.formatUTC(1774051200000)

        XCTAssertTrue(formatted.hasSuffix("Z"), "UTC format should end with Z")
        // ISO 8601 pattern
        let regex = try! NSRegularExpression(pattern: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"#)
        let range = NSRange(formatted.startIndex..., in: formatted)
        XCTAssertNotNil(regex.firstMatch(in: formatted, range: range),
                        "Should match ISO 8601 UTC format: \(formatted)")
    }

    /// captured_at_local: ISO 8601 with offset (yyyy-MM-dd'T'HH:mm:ssXXX)
    func test_dateFormat_local_iso8601WithOffset() {
        let formatted = exporter.formatLocal(1774051200000)

        // Should contain timezone offset like +09:00 or -05:00 or Z
        let regex = try! NSRegularExpression(pattern: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$"#)
        let range = NSRange(formatted.startIndex..., in: formatted)
        let hasOffset = regex.firstMatch(in: formatted, range: range) != nil
        let isUTC = formatted.hasSuffix("Z")
        XCTAssertTrue(hasOffset || isUTC,
                      "Should be ISO 8601 with timezone offset: \(formatted)")
    }

    // MARK: - Decimal

    /// 小数: ピリオド区切り (カンマではない)
    func test_decimal_periodSeparator_notComma() throws {
        let outputURL = tempDir.appendingPathComponent("test_decimal.csv")
        let sample = makePowerSample(avgWatts: 42.567)

        try exporter.exportRawPower(samples: [sample], to: outputURL)

        let content = try String(contentsOf: outputURL, encoding: .utf8)
        let cleanContent = content.replacingOccurrences(of: "\u{FEFF}", with: "")
        let lines = cleanContent.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        let dataFields = lines[1].components(separatedBy: ",")

        // avg_watts should use period as decimal separator
        let avgWattsStr = dataFields[2]
        XCTAssertTrue(avgWattsStr.contains("."), "Should use period as decimal separator")
        XCTAssertFalse(avgWattsStr.contains(","), "Should not use comma as decimal separator")
    }


    /// CSV セル: カンマ・クォート・改行を含む値は RFC 4180 互換で escape されること
    func test_csvCell_escapesCommaQuoteAndNewline() {
        let escaped = exporter.csvCell("en,\"bad\"\nnext")
        XCTAssertEqual(escaped, "\"en,\"\"bad\"\"\nnext\"")
    }

    /// CSV セル: 表計算ソフトで式として解釈されうる値を neutralize すること
    func test_csvCell_neutralizesFormulaInjectionPrefix() {
        XCTAssertEqual(exporter.csvCell("=cmd|'/C calc'!A0"), "'=cmd|'/C calc'!A0")
        XCTAssertEqual(exporter.csvCell("@SUM(1,2)"), "\"'@SUM(1,2)\"")
    }

    // MARK: - Multiple Rows

    /// 複数行出力: captured_at_ms 昇順
    func test_multipleRows_ascendingOrder() throws {
        let outputURL = tempDir.appendingPathComponent("test_multi.csv")
        let samples = [
            makePowerSample(avgWatts: 30.0, capturedAtMs: 1774051200000),
            makePowerSample(avgWatts: 50.0, capturedAtMs: 1774051260000),
            makePowerSample(avgWatts: 40.0, capturedAtMs: 1774051320000),
        ]

        try exporter.exportRawPower(samples: samples, to: outputURL)

        let content = try String(contentsOf: outputURL, encoding: .utf8)
        let cleanContent = content.replacingOccurrences(of: "\u{FEFF}", with: "")
        let lines = cleanContent.components(separatedBy: "\r\n").filter { !$0.isEmpty }

        XCTAssertEqual(lines.count, 4, "Header + 3 data rows")

        // Verify watts are in order
        let watts = lines[1...3].map { $0.components(separatedBy: ",")[2] }
        XCTAssertEqual(watts, ["30.0", "50.0", "40.0"])
    }

    // MARK: - Test Helpers

    private func makePowerSample(
        avgWatts: Double?,
        sourceLevel: PowerSample.SourceLevel = .a,
        status: PowerSample.SampleStatus = .success,
        capturedAtMs: Int64 = 1774051200000
    ) -> PowerSample {
        PowerSample(
            id: 1,
            capturedAtMs: capturedAtMs,
            avgWatts: avgWatts,
            sampleDurationSec: 60.0,
            sourceLevel: sourceLevel,
            status: status,
            parserStatus: .success,
            outlierFlag: 0,
            rawCaptureId: nil,
            errorCode: nil
        )
    }

    private func makeWifiSample(sentDelta: Int64, recvDelta: Int64) -> WifiSample {
        WifiSample(
            id: 1,
            capturedAtMs: 1774051200000,
            interfaceName: "en0",
            sentBytesTotal: 1_000_000,
            recvBytesTotal: 5_000_000,
            sentBytesDelta: sentDelta,
            recvBytesDelta: recvDelta,
            counterResetFlag: 0,
            status: .success,
            errorCode: nil
        )
    }

    private func makeDailyRollup() -> DailyRollup {
        DailyRollup(
            dateLocal: "2026-03-18",
            powerKwh: 1.008,
            wifiGb: 2.5,
            powerCostYen: 31.2,
            networkCostYen: 161.3,
            coverageRatioPower: 0.95,
            coverageRatioWifi: 0.98,
            sampleCountPower: 1368,
            sampleCountWifi: 8467,
            computedAtMs: 1742342400000
        )
    }
}
