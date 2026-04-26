import Foundation

/// CSV エクスポーター (付録C)
///
/// 時系列/日次集計を CSV ファイルに出力する。
/// - 文字コード: UTF-8 with BOM
/// - 改行: CRLF
/// - ヘッダー行あり
/// - 欠測値: 空文字 (0 と混同させない)
/// - 日付: ISO 8601
struct CSVExporter: Sendable {

    /// UTF-8 BOM
    static let utf8BOM = "\u{FEFF}"

    /// CRLF 改行
    static let crlf = "\r\n"

    // MARK: - Export Types

    /// エクスポート種別
    enum ExportType: String, Sendable {
        case rawPower = "raw_power"
        case rawWifi = "raw_wifi"
        case dailyRollup = "daily_rollup"
    }

    // MARK: - Raw Power

    /// raw_power CSV ヘッダー
    static let rawPowerHeader = "captured_at_utc,captured_at_local,avg_watts,sample_duration_sec,source_level,status,parser_status,outlier_flag,error_code"

    /// 電力サンプルを CSV 文字列にエクスポートする
    func exportRawPower(samples: [PowerSample], to outputURL: URL) throws {
        var csv = Self.utf8BOM
        csv += Self.rawPowerHeader + Self.crlf

        for sample in samples {
            let row = [
                formatUTC(sample.capturedAtMs),
                formatLocal(sample.capturedAtMs),
                csvCell(sample.avgWatts),
                csvCell(sample.sampleDurationSec),
                sample.sourceLevel.rawValue,
                sample.status.rawValue,
                sample.parserStatus.rawValue,
                csvCell(sample.outlierFlag),
                csvCell(sample.errorCode)
            ].joined(separator: ",")
            csv += row + Self.crlf
        }

        try csv.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Raw Wi-Fi

    /// raw_wifi CSV ヘッダー
    static let rawWifiHeader = "captured_at_utc,captured_at_local,interface_name,sent_bytes_delta,recv_bytes_delta,sent_bytes_total,recv_bytes_total,counter_reset_flag,status,error_code"

    /// Wi-Fi サンプルを CSV 文字列にエクスポートする
    func exportRawWifi(samples: [WifiSample], to outputURL: URL) throws {
        var csv = Self.utf8BOM
        csv += Self.rawWifiHeader + Self.crlf

        for sample in samples {
            let row = [
                formatUTC(sample.capturedAtMs),
                formatLocal(sample.capturedAtMs),
                sample.interfaceName,
                csvCell(sample.sentBytesDelta),
                csvCell(sample.recvBytesDelta),
                csvCell(sample.sentBytesTotal),
                csvCell(sample.recvBytesTotal),
                csvCell(sample.counterResetFlag),
                sample.status.rawValue,
                csvCell(sample.errorCode)
            ].joined(separator: ",")
            csv += row + Self.crlf
        }

        try csv.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Daily Rollup

    /// daily_rollup CSV ヘッダー
    static let dailyRollupHeader = "date_local,power_kwh,wifi_gb,power_cost_yen,network_cost_yen,coverage_ratio_power,coverage_ratio_wifi,sample_count_power,sample_count_wifi,computed_at_utc"

    /// 日次ロールアップを CSV 文字列にエクスポートする
    func exportDailyRollup(rollups: [DailyRollup], to outputURL: URL) throws {
        var csv = Self.utf8BOM
        csv += Self.dailyRollupHeader + Self.crlf

        for rollup in rollups {
            let row = [
                rollup.dateLocal,
                csvCell(rollup.powerKwh),
                csvCell(rollup.wifiGb),
                csvCell(rollup.powerCostYen),
                csvCell(rollup.networkCostYen),
                csvCell(rollup.coverageRatioPower),
                csvCell(rollup.coverageRatioWifi),
                csvCell(rollup.sampleCountPower),
                csvCell(rollup.sampleCountWifi),
                formatUTC(rollup.computedAtMs)
            ].joined(separator: ",")
            csv += row + Self.crlf
        }

        try csv.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Utility

    /// UTC 日付フォーマッタ
    private static let utcFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// ローカル日付フォーマッタ
    private static let localFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXX"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Epoch ms を UTC の ISO 8601 文字列に変換する
    ///
    /// 形式: yyyy-MM-dd'T'HH:mm:ss'Z'
    func formatUTC(_ epochMs: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(epochMs) / 1000.0)
        return Self.utcFormatter.string(from: date)
    }

    /// Epoch ms をローカルの ISO 8601 文字列に変換する
    ///
    /// 形式: yyyy-MM-dd'T'HH:mm:ssXXX (タイムゾーンオフセット付き)
    func formatLocal(_ epochMs: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(epochMs) / 1000.0)
        return Self.localFormatter.string(from: date)
    }

    /// 値を CSV セル文字列に変換する。nil の場合は空文字を返す。
    func csvCell<T>(_ value: T?) -> String {
        guard let v = value else { return "" }
        return "\(v)"
    }
}
