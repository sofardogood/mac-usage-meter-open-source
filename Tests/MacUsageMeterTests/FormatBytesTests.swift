import XCTest
@testable import MacUsageMeter

/// PopoverViewModel.formatBytes の単体テスト
///
/// 観点: バイト数から適応単位 (B, KB, MB, GB) への変換の正確性
/// 仕様書 G-002 に基づく
final class FormatBytesTests: XCTestCase {

    // MARK: - Bytes (< 1,000)

    /// 0 バイト → "0 B"
    func test_formatBytes_zero_zeroB() {
        XCTAssertEqual(PopoverViewModel.formatBytes(0), "0 B")
    }

    /// 1 バイト → "1 B"
    func test_formatBytes_one_oneB() {
        XCTAssertEqual(PopoverViewModel.formatBytes(1), "1 B")
    }

    /// 999 バイト → "999 B"
    func test_formatBytes_999_nineNineNineB() {
        XCTAssertEqual(PopoverViewModel.formatBytes(999), "999 B")
    }

    // MARK: - Kilobytes (1,000 〜 999,999)

    /// 1,000 バイト → "1.0 KB"
    func test_formatBytes_1000_oneKB() {
        XCTAssertEqual(PopoverViewModel.formatBytes(1_000), "1.0 KB")
    }

    /// 1,500 バイト → "1.5 KB"
    func test_formatBytes_1500_onePointFiveKB() {
        XCTAssertEqual(PopoverViewModel.formatBytes(1_500), "1.5 KB")
    }

    /// 999,999 バイト → "1000.0 KB" (境界直前)
    func test_formatBytes_999999_almostOneMB() {
        let result = PopoverViewModel.formatBytes(999_999)
        XCTAssertTrue(result.hasSuffix("KB"), "Should be in KB: \(result)")
    }

    // MARK: - Megabytes (1,000,000 〜 999,999,999)

    /// 1,000,000 バイト → "1.0 MB"
    func test_formatBytes_oneMillion_oneMB() {
        XCTAssertEqual(PopoverViewModel.formatBytes(1_000_000), "1.0 MB")
    }

    /// 500,000,000 バイト → "500.0 MB"
    func test_formatBytes_500Million_500MB() {
        XCTAssertEqual(PopoverViewModel.formatBytes(500_000_000), "500.0 MB")
    }

    /// 999,999,999 バイト → MB 単位
    func test_formatBytes_justUnderOneGB_inMB() {
        let result = PopoverViewModel.formatBytes(999_999_999)
        XCTAssertTrue(result.hasSuffix("MB"), "Should be in MB: \(result)")
    }

    // MARK: - Gigabytes (>= 1,000,000,000)

    /// 1,000,000,000 バイト → "1.00 GB"
    func test_formatBytes_oneBillion_oneGB() {
        XCTAssertEqual(PopoverViewModel.formatBytes(1_000_000_000), "1.00 GB")
    }

    /// 1,500,000,000 バイト → "1.50 GB"
    func test_formatBytes_onePointFiveBillion_onePointFiveGB() {
        XCTAssertEqual(PopoverViewModel.formatBytes(1_500_000_000), "1.50 GB")
    }

    /// 15,750,000,000 バイト → "15.75 GB"
    func test_formatBytes_15Billion_15pointSevenFiveGB() {
        XCTAssertEqual(PopoverViewModel.formatBytes(15_750_000_000), "15.75 GB")
    }

    /// 100 GB 超
    func test_formatBytes_100GB_correctFormat() {
        let result = PopoverViewModel.formatBytes(100_000_000_000)
        XCTAssertEqual(result, "100.00 GB")
    }

    // MARK: - GB は小数2桁、MB/KB は小数1桁

    /// GB は小数2桁表示
    func test_formatBytes_gbTwoDecimalPlaces() {
        let result = PopoverViewModel.formatBytes(1_230_000_000)
        XCTAssertEqual(result, "1.23 GB")
    }

    /// MB は小数1桁表示
    func test_formatBytes_mbOneDecimalPlace() {
        let result = PopoverViewModel.formatBytes(1_230_000)
        XCTAssertEqual(result, "1.2 MB")
    }

    /// KB は小数1桁表示
    func test_formatBytes_kbOneDecimalPlace() {
        let result = PopoverViewModel.formatBytes(1_230)
        XCTAssertEqual(result, "1.2 KB")
    }
}
