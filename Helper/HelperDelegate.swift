import Foundation
import Shared

/// Helper XPC リスナーデリゲート
///
/// NSXPCListenerDelegate を実装し、接続の受理と HelperProtocol の公開を行う。
/// 接続受理時に audit token による peer 認証を実施する (第12.1節)。
final class HelperDelegate: NSObject, NSXPCListenerDelegate {

    /// Helper バージョン
    static let helperVersion = "1.0.0"

    /// プロトコルバージョン (第11.4節)
    static let protocolVersion = 1

    /// XPC Peer バリデータ
    private let peerValidator = XPCPeerValidator()

    /// powermetrics 実行器
    private let powerMetricsExecutor = PowerMetricsExecutor()

    /// powermetrics パーサー
    private let powerMetricsParser = PowerMetricsParser()

    /// Wi-Fi カウンタリーダー
    private let wifiCounterReader = WifiCounterReader()

    /// 能力検出
    private let capabilityProbe = CapabilityProbe()

    /// 起動時刻
    private let startedAt = Date()

    /// 累計電力サンプル数
    private var totalPowerSamples: Int = 0

    /// 累計 Wi-Fi スナップショット数
    private var totalWifiSnapshots: Int = 0

    /// 連続失敗回数
    private var consecutiveFailures: Int = 0

    /// 最終電力サンプル時刻
    private var lastPowerSampleAtMs: Int64?

    /// 最終 Wi-Fi スナップショット時刻
    private var lastWifiSnapshotAtMs: Int64?

    /// 最終エラーコード
    private var lastErrorCode: String?

    /// デバッグ採取有効フラグ
    private var debugCaptureEnabled: Bool = false

    /// 能力検出結果キャッシュ
    private var cachedProbeResult: CapabilityProbe.ProbeResult?

    // MARK: - NSXPCListenerDelegate

    /// 新しい接続を受理するか判定する
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // audit token による peer 認証
        guard peerValidator.validatePeer(newConnection) else {
            return false
        }

        // プロトコル設定
        newConnection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        newConnection.exportedObject = self

        newConnection.invalidationHandler = {
            // 接続無効化時のクリーンアップ (必要なら)
        }

        newConnection.resume()
        return true
    }
}

// MARK: - HelperProtocol Implementation

extension HelperDelegate: HelperProtocol {

    /// PING: 疎通確認
    func ping(withReply reply: @escaping (Bool) -> Void) {
        reply(true)
    }

    /// GET_SERVICE_STATUS: 登録状態・権限状態を取得する
    func getServiceStatus(withReply reply: @escaping (Data) -> Void) {
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        // Helper は root で動作しているので権限は granted
        let response = ServiceStatusResponse(
            serviceState: .ready,
            privilegeState: .granted,
            protocolVersion: Self.protocolVersion,
            lastSuccessAtMs: lastPowerSampleAtMs ?? lastWifiSnapshotAtMs,
            lastErrorCode: lastErrorCode,
            helperVersion: Self.helperVersion
        )

        let envelope = XPCResponseEnvelope<ServiceStatusResponse>(
            result: .ok,
            errorCode: nil,
            message: nil,
            capturedAtMs: now,
            data: response
        )

        if let data = try? JSONEncoder().encode(envelope) {
            reply(data)
        } else {
            replyError(reply, errorCode: "IPC-002", message: "Failed to encode service status")
        }
    }

    /// GET_CAPABILITIES: 対応機種・利用可能プロファイルを取得する
    func getCapabilities(withReply reply: @escaping (Data) -> Void) {
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        // 能力検出 (キャッシュがあればそれを使う)
        let probeResult: CapabilityProbe.ProbeResult
        if let cached = cachedProbeResult {
            probeResult = cached
        } else {
            probeResult = capabilityProbe.probe()
            cachedProbeResult = probeResult
        }

        let profiles = probeResult.profiles.map {
            CapabilitiesResponse.SamplingProfile(
                profileId: $0.profileId,
                sourceLevel: $0.sourceLevel,
                expectedMetricKeys: $0.expectedMetricKeys
            )
        }

        let hardwareFamily: CapabilitiesResponse.HardwareFamily
        switch probeResult.hardwareFamily {
        case .appleSilicon: hardwareFamily = .appleSilicon
        case .intel: hardwareFamily = .intel
        case .unknown: hardwareFamily = .unknown
        }

        let response = CapabilitiesResponse(
            hardwareFamily: hardwareFamily,
            osMajorVersion: probeResult.osMajorVersion,
            profiles: profiles
        )

        let envelope = XPCResponseEnvelope<CapabilitiesResponse>(
            result: .ok,
            errorCode: nil,
            message: nil,
            capturedAtMs: now,
            data: response
        )

        if let data = try? JSONEncoder().encode(envelope) {
            reply(data)
        } else {
            replyError(reply, errorCode: "IPC-003", message: "Failed to encode capabilities")
        }
    }

    /// REQUEST_POWER_SAMPLE: 単発電力サンプルを取得する
    func requestPowerSample(profileId: String, timeoutSec: Int, collectDebugRaw: Bool, withReply reply: @escaping (Data) -> Void) {
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        do {
            let result = try powerMetricsExecutor.execute(timeoutSec: timeoutSec)

            // デバッグ生データ用
            let rawCaptureId: String? = collectDebugRaw ? UUID().uuidString : nil

            if result.exitCode != 0 {
                consecutiveFailures += 1
                lastErrorCode = "PWR-001"
                let response = PowerSampleResponse(
                    status: "fail",
                    sourceLevel: "C",
                    parserStatus: "fail",
                    avgWatts: nil,
                    cpuWatts: nil,
                    gpuWatts: nil,
                    aneWatts: nil,
                    sampleDurationSec: nil,
                    missingKeys: nil,
                    rawCaptureId: rawCaptureId,
                    errorCode: "PWR-001"
                )
                let envelope = XPCResponseEnvelope<PowerSampleResponse>(
                    result: .error,
                    errorCode: "PWR-001",
                    message: "powermetrics exited with code \(result.exitCode)",
                    capturedAtMs: now,
                    data: response
                )
                if let data = try? JSONEncoder().encode(envelope) { reply(data) }
                return
            }

            let parseResult = powerMetricsParser.parse(result.stdout)

            totalPowerSamples += 1
            lastPowerSampleAtMs = now

            let status: String
            if parseResult.avgWatts != nil {
                consecutiveFailures = 0
                lastErrorCode = nil
                status = parseResult.parserStatus == "success" ? "success" : "partial"
            } else {
                consecutiveFailures += 1
                lastErrorCode = "PWR-003"
                status = parseResult.sourceLevel == "C" ? "missing" : "fail"
            }

            let response = PowerSampleResponse(
                status: status,
                sourceLevel: parseResult.sourceLevel,
                parserStatus: parseResult.parserStatus,
                avgWatts: parseResult.avgWatts,
                cpuWatts: parseResult.cpuWatts,
                gpuWatts: parseResult.gpuWatts,
                aneWatts: parseResult.aneWatts,
                sampleDurationSec: parseResult.sampleDurationSec,
                missingKeys: parseResult.missingKeys.isEmpty ? nil : parseResult.missingKeys,
                rawCaptureId: rawCaptureId,
                errorCode: parseResult.avgWatts == nil ? "PWR-003" : nil
            )

            let resultStatus: XPCResponseEnvelope<PowerSampleResponse>.ResultStatus = parseResult.avgWatts != nil ? .ok : .partial
            let envelope = XPCResponseEnvelope<PowerSampleResponse>(
                result: resultStatus,
                errorCode: response.errorCode,
                message: nil,
                capturedAtMs: now,
                data: response
            )

            if let data = try? JSONEncoder().encode(envelope) { reply(data) }

        } catch let error as PowerMetricsError {
            consecutiveFailures += 1

            let errorCode: String
            switch error {
            case .timeout: errorCode = "PWR-004"
            case .executionFailed: errorCode = "PWR-001"
            case .parseFailed: errorCode = "PWR-003"
            }
            lastErrorCode = errorCode

            let response = PowerSampleResponse(
                status: "fail",
                sourceLevel: "C",
                parserStatus: "fail",
                avgWatts: nil,
                cpuWatts: nil,
                gpuWatts: nil,
                aneWatts: nil,
                sampleDurationSec: nil,
                missingKeys: nil,
                rawCaptureId: nil,
                errorCode: errorCode
            )

            let envelope = XPCResponseEnvelope<PowerSampleResponse>(
                result: .error,
                errorCode: errorCode,
                message: error.localizedDescription,
                capturedAtMs: now,
                data: response
            )

            if let data = try? JSONEncoder().encode(envelope) { reply(data) }

        } catch {
            replyError(reply, errorCode: "PWR-001", message: error.localizedDescription)
        }
    }

    /// REQUEST_WIFI_SNAPSHOT: Wi-Fi カウンタを取得する
    func requestWifiSnapshot(withReply reply: @escaping (Data) -> Void) {
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        do {
            let snapshot = try wifiCounterReader.readCounters()

            totalWifiSnapshots += 1
            lastWifiSnapshotAtMs = now

            let response = WifiSnapshotResponse(
                status: "success",
                interfaceName: snapshot.interfaceName,
                sentBytesTotal: snapshot.sentBytesTotal,
                recvBytesTotal: snapshot.recvBytesTotal,
                errorCode: nil
            )

            let envelope = XPCResponseEnvelope<WifiSnapshotResponse>(
                result: .ok,
                errorCode: nil,
                message: nil,
                capturedAtMs: now,
                data: response
            )

            if let data = try? JSONEncoder().encode(envelope) { reply(data) }

        } catch let error as WifiCounterError {
            let errorCode: String
            let status: String
            switch error {
            case .interfaceUnknown:
                errorCode = "NET-001"
                status = "missing"
            case .snapshotFailed:
                errorCode = "NET-003"
                status = "fail"
            }

            let response = WifiSnapshotResponse(
                status: status,
                interfaceName: nil,
                sentBytesTotal: nil,
                recvBytesTotal: nil,
                errorCode: errorCode
            )

            let envelope = XPCResponseEnvelope<WifiSnapshotResponse>(
                result: .error,
                errorCode: errorCode,
                message: error.localizedDescription,
                capturedAtMs: now,
                data: response
            )

            if let data = try? JSONEncoder().encode(envelope) { reply(data) }

        } catch {
            replyError(reply, errorCode: "NET-003", message: error.localizedDescription)
        }
    }

    /// RELOAD_PRIVILEGE_STATE: 権限状態を再確認する
    func reloadPrivilegeState(withReply reply: @escaping (Data) -> Void) {
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        // Helper は root で動作 → 権限は常に granted
        let response = PrivilegeStateResponse(
            privilegeState: "granted",
            errorCode: nil
        )

        let envelope = XPCResponseEnvelope<PrivilegeStateResponse>(
            result: .ok,
            errorCode: nil,
            message: nil,
            capturedAtMs: now,
            data: response
        )

        if let data = try? JSONEncoder().encode(envelope) { reply(data) }
    }

    /// COLLECT_HEALTH_REPORT: 診断情報を取得する
    func collectHealthReport(withReply reply: @escaping (Data) -> Void) {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let uptimeSec = Int(Date().timeIntervalSince(startedAt))

        let response = HealthReportResponse(
            helperPid: Int(ProcessInfo.processInfo.processIdentifier),
            uptimeSec: uptimeSec,
            helperVersion: Self.helperVersion,
            lastPowerSampleAtMs: lastPowerSampleAtMs,
            lastWifiSnapshotAtMs: lastWifiSnapshotAtMs,
            totalPowerSamples: totalPowerSamples,
            totalWifiSnapshots: totalWifiSnapshots,
            consecutiveFailures: consecutiveFailures,
            errorCode: lastErrorCode
        )

        let envelope = XPCResponseEnvelope<HealthReportResponse>(
            result: .ok,
            errorCode: nil,
            message: nil,
            capturedAtMs: now,
            data: response
        )

        if let data = try? JSONEncoder().encode(envelope) { reply(data) }
    }

    /// ROTATE_DEBUG_CAPTURE: デバッグ採取の切替
    func rotateDebugCapture(enabled: Bool, withReply reply: @escaping (Data) -> Void) {
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        debugCaptureEnabled = enabled

        let response = DebugCaptureResponse(
            currentState: debugCaptureEnabled,
            errorCode: nil
        )

        let envelope = XPCResponseEnvelope<DebugCaptureResponse>(
            result: .ok,
            errorCode: nil,
            message: nil,
            capturedAtMs: now,
            data: response
        )

        if let data = try? JSONEncoder().encode(envelope) { reply(data) }
    }

    // MARK: - Private Helpers

    /// エラーレスポンスを返す汎用ヘルパー
    private func replyError(_ reply: @escaping (Data) -> Void, errorCode: String, message: String) {
        struct EmptyData: Codable {}
        let envelope = XPCResponseEnvelope<EmptyData>(
            result: .error,
            errorCode: errorCode,
            message: message,
            capturedAtMs: Int64(Date().timeIntervalSince1970 * 1000),
            data: nil
        )
        if let data = try? JSONEncoder().encode(envelope) {
            reply(data)
        } else {
            reply(Data())
        }
    }
}
