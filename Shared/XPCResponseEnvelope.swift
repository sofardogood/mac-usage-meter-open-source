import Foundation

/// XPC 共通レスポンス Envelope (付録A.1)
///
/// 全 XPC コマンドのレスポンスを統一的にラップする。
/// Data パラメータを JSONDecoder でデシリアライズする。
public struct XPCResponseEnvelope<T: Codable & Sendable>: Codable, Sendable {
    /// 結果ステータス
    public let result: ResultStatus

    /// エラーコード (エラー時のみ)
    public let errorCode: String?

    /// 人間可読メッセージ
    public let message: String?

    /// 採取時刻 (UTC Epoch ms)
    public let capturedAtMs: Int64?

    /// レスポンスデータ
    public let data: T?

    public init(result: ResultStatus, errorCode: String?, message: String?, capturedAtMs: Int64?, data: T?) {
        self.result = result
        self.errorCode = errorCode
        self.message = message
        self.capturedAtMs = capturedAtMs
        self.data = data
    }

    /// 結果ステータス
    public enum ResultStatus: String, Codable, Sendable {
        case ok
        case partial
        case error
    }
}

// MARK: - GET_SERVICE_STATUS Response (付録A.3)

/// サービスステータスレスポンス
public struct ServiceStatusResponse: Codable, Sendable {
    public let serviceState: ServiceState
    public let privilegeState: PrivilegeState
    public let protocolVersion: Int
    public let lastSuccessAtMs: Int64?
    public let lastErrorCode: String?
    public let helperVersion: String

    public init(serviceState: ServiceState, privilegeState: PrivilegeState, protocolVersion: Int, lastSuccessAtMs: Int64?, lastErrorCode: String?, helperVersion: String) {
        self.serviceState = serviceState
        self.privilegeState = privilegeState
        self.protocolVersion = protocolVersion
        self.lastSuccessAtMs = lastSuccessAtMs
        self.lastErrorCode = lastErrorCode
        self.helperVersion = helperVersion
    }

    public enum ServiceState: String, Codable, Sendable {
        case ready
        case limitedReady = "limited-ready"
        case notRegistered = "not-registered"
        case degraded
    }

    public enum PrivilegeState: String, Codable, Sendable {
        case granted
        case denied
        case unknown
    }
}

// MARK: - GET_CAPABILITIES Response (付録A.4)

/// 能力レスポンス
public struct CapabilitiesResponse: Codable, Sendable {
    public let hardwareFamily: HardwareFamily
    public let osMajorVersion: Int
    public let profiles: [SamplingProfile]

    public init(hardwareFamily: HardwareFamily, osMajorVersion: Int, profiles: [SamplingProfile]) {
        self.hardwareFamily = hardwareFamily
        self.osMajorVersion = osMajorVersion
        self.profiles = profiles
    }

    public enum HardwareFamily: String, Codable, Sendable {
        case appleSilicon = "apple_silicon"
        case intel
        case unknown
    }

    public struct SamplingProfile: Codable, Sendable {
        public let profileId: String
        public let sourceLevel: String
        public let expectedMetricKeys: [String]

        public init(profileId: String, sourceLevel: String, expectedMetricKeys: [String]) {
            self.profileId = profileId
            self.sourceLevel = sourceLevel
            self.expectedMetricKeys = expectedMetricKeys
        }
    }
}

// MARK: - REQUEST_POWER_SAMPLE Response (付録A.5)

/// 電力サンプルレスポンス
public struct PowerSampleResponse: Codable, Sendable {
    public let status: String
    public let sourceLevel: String
    public let parserStatus: String
    public let avgWatts: Double?
    public let cpuWatts: Double?
    public let gpuWatts: Double?
    public let aneWatts: Double?
    public let sampleDurationSec: Double?
    public let missingKeys: [String]?
    public let rawCaptureId: String?
    public let errorCode: String?

    public init(status: String, sourceLevel: String, parserStatus: String, avgWatts: Double?, cpuWatts: Double?, gpuWatts: Double?, aneWatts: Double?, sampleDurationSec: Double?, missingKeys: [String]?, rawCaptureId: String?, errorCode: String?) {
        self.status = status
        self.sourceLevel = sourceLevel
        self.parserStatus = parserStatus
        self.avgWatts = avgWatts
        self.cpuWatts = cpuWatts
        self.gpuWatts = gpuWatts
        self.aneWatts = aneWatts
        self.sampleDurationSec = sampleDurationSec
        self.missingKeys = missingKeys
        self.rawCaptureId = rawCaptureId
        self.errorCode = errorCode
    }
}

// MARK: - REQUEST_WIFI_SNAPSHOT Response (付録A.6)

/// Wi-Fi スナップショットレスポンス
public struct WifiSnapshotResponse: Codable, Sendable {
    public let status: String
    public let interfaceName: String?
    public let sentBytesTotal: Int64?
    public let recvBytesTotal: Int64?
    public let errorCode: String?

    public init(status: String, interfaceName: String?, sentBytesTotal: Int64?, recvBytesTotal: Int64?, errorCode: String?) {
        self.status = status
        self.interfaceName = interfaceName
        self.sentBytesTotal = sentBytesTotal
        self.recvBytesTotal = recvBytesTotal
        self.errorCode = errorCode
    }
}

// MARK: - RELOAD_PRIVILEGE_STATE Response (付録A.7)

/// 権限状態レスポンス
public struct PrivilegeStateResponse: Codable, Sendable {
    public let privilegeState: String
    public let errorCode: String?

    public init(privilegeState: String, errorCode: String?) {
        self.privilegeState = privilegeState
        self.errorCode = errorCode
    }
}

// MARK: - COLLECT_HEALTH_REPORT Response (付録A.8)

/// ヘルスレポートレスポンス
public struct HealthReportResponse: Codable, Sendable {
    public let helperPid: Int
    public let uptimeSec: Int
    public let helperVersion: String
    public let lastPowerSampleAtMs: Int64?
    public let lastWifiSnapshotAtMs: Int64?
    public let totalPowerSamples: Int
    public let totalWifiSnapshots: Int
    public let consecutiveFailures: Int
    public let errorCode: String?

    public init(helperPid: Int, uptimeSec: Int, helperVersion: String, lastPowerSampleAtMs: Int64?, lastWifiSnapshotAtMs: Int64?, totalPowerSamples: Int, totalWifiSnapshots: Int, consecutiveFailures: Int, errorCode: String?) {
        self.helperPid = helperPid
        self.uptimeSec = uptimeSec
        self.helperVersion = helperVersion
        self.lastPowerSampleAtMs = lastPowerSampleAtMs
        self.lastWifiSnapshotAtMs = lastWifiSnapshotAtMs
        self.totalPowerSamples = totalPowerSamples
        self.totalWifiSnapshots = totalWifiSnapshots
        self.consecutiveFailures = consecutiveFailures
        self.errorCode = errorCode
    }
}

// MARK: - ROTATE_DEBUG_CAPTURE Response (付録A.9)

/// デバッグキャプチャレスポンス
public struct DebugCaptureResponse: Codable, Sendable {
    public let currentState: Bool
    public let errorCode: String?

    public init(currentState: Bool, errorCode: String?) {
        self.currentState = currentState
        self.errorCode = errorCode
    }
}
