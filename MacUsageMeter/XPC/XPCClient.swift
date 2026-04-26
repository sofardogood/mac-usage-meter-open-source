import Foundation
import os.log

/// XPC クライアント (第11章)
///
/// UI App から Privileged Helper への NSXPCConnection を管理する。
/// MachService 名: <bundle-id>.helper
final class XPCClient: @unchecked Sendable {

    /// MachService 名
    static let machServiceName = "com.macusagemeter.helper"

    /// UI App が要求する最小プロトコルバージョン
    static let minRequiredProtocolVersion = 1

    /// XPC 接続
    private var connection: NSXPCConnection?

    /// 接続中断ハンドラ
    var onInterruption: (() -> Void)?

    /// 接続無効化ハンドラ
    var onInvalidation: (() -> Void)?

    /// Helper 接続を試みるかどうか (false の場合すべてのコマンドが即座に notConnected を返す)
    var helperConnectionEnabled: Bool = true

    /// ロガー
    private static let logger = Logger(subsystem: "com.macusagemeter", category: "XPCClient")

    /// 接続ロック
    private let lock = NSLock()

    /// デフォルトタイムアウト (秒)
    private static let defaultTimeoutSec: UInt64 = 5

    // MARK: - Initialization

    init() {}

    deinit {
        disconnect()
    }

    // MARK: - Connection Management

    /// XPC 接続を確立する
    ///
    /// `helperConnectionEnabled` が false の場合は接続を試みない。
    /// machServiceName ベースで接続する（ローカルモード・本番とも同一）。
    func connect() {
        lock.lock()
        defer { lock.unlock() }

        guard helperConnectionEnabled else {
            Self.logger.info("Helper connection disabled, skipping connect")
            return
        }

        if connection != nil { return }

        let conn = NSXPCConnection(machServiceName: Self.machServiceName, options: .privileged)
        Self.logger.info("Connecting to machService: \(Self.machServiceName)")

        conn.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)

        conn.interruptionHandler = { [weak self] in
            Self.logger.warning("XPC connection interrupted")
            self?.onInterruption?()
        }

        conn.invalidationHandler = { [weak self] in
            Self.logger.warning("XPC connection invalidated")
            self?.lock.lock()
            self?.connection = nil
            self?.lock.unlock()
            self?.onInvalidation?()
        }

        conn.resume()
        connection = conn
        Self.logger.info("XPC connection established")
    }

    /// XPC 接続を切断する
    func disconnect() {
        lock.lock()
        defer { lock.unlock() }

        connection?.invalidate()
        connection = nil
    }

    /// 接続が確立しているかどうか
    var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return connection != nil
    }

    /// Helper のプロキシを取得する
    private func proxy() throws -> HelperProtocol {
        lock.lock()
        let conn = connection
        lock.unlock()

        guard let conn = conn else {
            throw XPCError.notConnected
        }

        guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
            Self.logger.error("XPC proxy error: \(error.localizedDescription)")
        }) as? HelperProtocol else {
            throw XPCError.proxyFailed
        }

        return proxy
    }

    // MARK: - Timeout Helpers

    /// タイムアウト付きで XPC コールを実行する
    private func withTimeout<T: Sendable>(
        seconds: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw XPCError.timeout
            }
            guard let result = try await group.next() else {
                throw XPCError.timeout
            }
            group.cancelAll()
            return result
        }
    }

    // MARK: - Commands

    /// PING: 疎通確認 (タイムアウト: 2秒)
    func ping() async throws -> Bool {
        let proxy = try proxy()
        return try await withTimeout(seconds: 2) {
            try await withCheckedThrowingContinuation { continuation in
                proxy.ping { result in
                    continuation.resume(returning: result)
                }
            }
        }
    }

    /// GET_SERVICE_STATUS: 登録状態・権限状態を取得する (タイムアウト: 3秒)
    func getServiceStatus() async throws -> ServiceStatusResponse {
        let proxy = try proxy()
        let data: Data = try await withTimeout(seconds: 3) {
            try await withCheckedThrowingContinuation { continuation in
                proxy.getServiceStatus { data in
                    continuation.resume(returning: data)
                }
            }
        }
        let envelope = try JSONDecoder().decode(XPCResponseEnvelope<ServiceStatusResponse>.self, from: data)
        guard let response = envelope.data else {
            throw XPCError.invalidResponse(errorCode: envelope.errorCode)
        }
        return response
    }

    /// GET_CAPABILITIES: 能力検出結果を取得する (タイムアウト: 5秒)
    func getCapabilities() async throws -> CapabilitiesResponse {
        let proxy = try proxy()
        let data: Data = try await withTimeout(seconds: 5) {
            try await withCheckedThrowingContinuation { continuation in
                proxy.getCapabilities { data in
                    continuation.resume(returning: data)
                }
            }
        }
        let envelope = try JSONDecoder().decode(XPCResponseEnvelope<CapabilitiesResponse>.self, from: data)
        guard let response = envelope.data else {
            throw XPCError.invalidResponse(errorCode: envelope.errorCode)
        }
        return response
    }

    /// REQUEST_POWER_SAMPLE: 電力サンプルを取得する (タイムアウト: 12秒)
    func requestPowerSample(profileId: String, timeoutSec: Int, collectDebugRaw: Bool) async throws -> PowerSampleResponse {
        let proxy = try proxy()
        let timeoutSeconds = UInt64(timeoutSec) + 4 // IPC マージン
        let data: Data = try await withTimeout(seconds: timeoutSeconds) {
            try await withCheckedThrowingContinuation { continuation in
                proxy.requestPowerSample(profileId: profileId, timeoutSec: timeoutSec, collectDebugRaw: collectDebugRaw) { data in
                    continuation.resume(returning: data)
                }
            }
        }
        let envelope = try JSONDecoder().decode(XPCResponseEnvelope<PowerSampleResponse>.self, from: data)
        guard let response = envelope.data else {
            throw XPCError.invalidResponse(errorCode: envelope.errorCode)
        }
        return response
    }

    /// REQUEST_WIFI_SNAPSHOT: Wi-Fi カウンタを取得する (タイムアウト: 5秒)
    func requestWifiSnapshot() async throws -> WifiSnapshotResponse {
        let proxy = try proxy()
        let data: Data = try await withTimeout(seconds: 5) {
            try await withCheckedThrowingContinuation { continuation in
                proxy.requestWifiSnapshot { data in
                    continuation.resume(returning: data)
                }
            }
        }
        let envelope = try JSONDecoder().decode(XPCResponseEnvelope<WifiSnapshotResponse>.self, from: data)
        guard let response = envelope.data else {
            throw XPCError.invalidResponse(errorCode: envelope.errorCode)
        }
        return response
    }

    /// RELOAD_PRIVILEGE_STATE: 権限状態を再確認する (タイムアウト: 3秒)
    func reloadPrivilegeState() async throws -> PrivilegeStateResponse {
        let proxy = try proxy()
        let data: Data = try await withTimeout(seconds: 3) {
            try await withCheckedThrowingContinuation { continuation in
                proxy.reloadPrivilegeState { data in
                    continuation.resume(returning: data)
                }
            }
        }
        let envelope = try JSONDecoder().decode(XPCResponseEnvelope<PrivilegeStateResponse>.self, from: data)
        guard let response = envelope.data else {
            throw XPCError.invalidResponse(errorCode: envelope.errorCode)
        }
        return response
    }

    /// COLLECT_HEALTH_REPORT: 診断情報を取得する (タイムアウト: 5秒)
    func collectHealthReport() async throws -> HealthReportResponse {
        let proxy = try proxy()
        let data: Data = try await withTimeout(seconds: 5) {
            try await withCheckedThrowingContinuation { continuation in
                proxy.collectHealthReport { data in
                    continuation.resume(returning: data)
                }
            }
        }
        let envelope = try JSONDecoder().decode(XPCResponseEnvelope<HealthReportResponse>.self, from: data)
        guard let response = envelope.data else {
            throw XPCError.invalidResponse(errorCode: envelope.errorCode)
        }
        return response
    }

    /// ROTATE_DEBUG_CAPTURE: デバッグ採取の切替 (タイムアウト: 3秒)
    func rotateDebugCapture(enabled: Bool) async throws -> DebugCaptureResponse {
        let proxy = try proxy()
        let data: Data = try await withTimeout(seconds: 3) {
            try await withCheckedThrowingContinuation { continuation in
                proxy.rotateDebugCapture(enabled: enabled) { data in
                    continuation.resume(returning: data)
                }
            }
        }
        let envelope = try JSONDecoder().decode(XPCResponseEnvelope<DebugCaptureResponse>.self, from: data)
        guard let response = envelope.data else {
            throw XPCError.invalidResponse(errorCode: envelope.errorCode)
        }
        return response
    }
}

// MARK: - XPC Errors

enum XPCError: Error, LocalizedError {
    case notConnected
    case proxyFailed
    case invalidResponse(errorCode: String?)
    case timeout
    case helperNotAvailable

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "XPC connection not established"
        case .proxyFailed:
            return "Failed to create XPC proxy"
        case .invalidResponse(let code):
            return "Invalid XPC response (errorCode=\(code ?? "none"))"
        case .timeout:
            return "XPC request timed out"
        case .helperNotAvailable:
            return "Helper process is not available"
        }
    }
}
