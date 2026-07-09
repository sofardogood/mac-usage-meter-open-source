import Foundation

/// powermetrics 実行器 (第7.1節)
///
/// Helper が Process() で子プロセスとして powermetrics を起動する。
/// コマンドパス: /usr/bin/powermetrics (フルパス固定、PATH 参照しない)
/// 環境変数: 空の辞書
/// currentDirectoryURL: /
struct PowerMetricsExecutor: Sendable {

    /// powermetrics の絶対パス
    static let executablePath = "/usr/bin/powermetrics"

    /// powermetrics 引数テンプレート
    static let baseArguments = ["--sample-count", "1", "-f", "plist", "--samplers", "cpu_power"]

    /// デバッグキャプチャに記録するコマンド表現
    static let commandDescription = "\(executablePath) --sample-count 1 --sample-rate 500 -f plist --samplers cpu_power"

    // MARK: - Execution

    /// powermetrics を実行し plist 出力を取得する
    ///
    /// - Parameters:
    ///   - sampleRateMs: サンプルレート (ミリ秒)
    ///   - timeoutSec: タイムアウト秒数 (既定 8 秒)
    /// - Returns: 実行結果
    /// - Throws: PWR-001 (実行不可)、PWR-004 (タイムアウト)
    func execute(sampleRateMs: Int = 500, timeoutSec: Int = 8) throws -> ExecutionResult {
        let startTime = Date()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.executablePath)
        process.arguments = ["--sample-count", "1", "--sample-rate", "\(sampleRateMs)", "-f", "plist", "--samplers", "cpu_power"]
        process.currentDirectoryURL = URL(fileURLWithPath: "/")
        process.environment = [:] // 環境変数は空

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw PowerMetricsError.executionFailed(message: error.localizedDescription)
        }

        // タイムアウト管理
        let timeoutWorkItem = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(timeoutSec), execute: timeoutWorkItem)

        process.waitUntilExit()
        timeoutWorkItem.cancel()

        let elapsed = Date().timeIntervalSince(startTime)

        // タイムアウト判定: プロセスが terminate された場合
        if process.terminationReason == .uncaughtSignal && elapsed >= Double(timeoutSec) - 0.5 {
            throw PowerMetricsError.timeout(timeoutSec: timeoutSec)
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        return ExecutionResult(
            stdout: stdout,
            stderr: stderr,
            exitCode: process.terminationStatus,
            elapsedSec: elapsed
        )
    }

    /// Capability probe 用の単発実行
    func executeProbe() throws -> ExecutionResult {
        return try execute(sampleRateMs: 1000, timeoutSec: 15)
    }

    // MARK: - Types

    /// 実行結果
    struct ExecutionResult: Sendable {
        /// 標準出力 (plist XML)
        let stdout: String

        /// 標準エラー出力
        let stderr: String

        /// 終了コード
        let exitCode: Int32

        /// 実行にかかった時間 (秒)
        let elapsedSec: Double
    }
}

// MARK: - PowerMetrics Errors

enum PowerMetricsError: Error, LocalizedError {
    case executionFailed(message: String)
    case timeout(timeoutSec: Int)
    case parseFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .executionFailed(let msg):
            return "PWR-001: powermetrics execution failed: \(msg)"
        case .timeout(let sec):
            return "PWR-004: powermetrics timed out after \(sec)s"
        case .parseFailed(let msg):
            return "PWR-003: powermetrics parse failed: \(msg)"
        }
    }
}
