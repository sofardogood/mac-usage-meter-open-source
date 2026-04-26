import Foundation
import CoreWLAN
import Darwin

/// Wi-Fi カウンタリーダー (第8.1節)
///
/// getifaddrs() + if_data から Wi-Fi インターフェースの送受信バイト数を取得する。
/// インターフェース名は CWWiFiClient.shared().interface()?.interfaceName で動的に特定する。
struct WifiCounterReader: Sendable {

    // MARK: - Read

    /// Wi-Fi カウンタを読み取る
    ///
    /// 1. CWWiFiClient でアクティブな Wi-Fi インターフェース名を取得
    /// 2. getifaddrs() で ifaddrs リストを取得
    /// 3. 対象インターフェースの ifa_data を if_data にキャスト
    /// 4. ifi_ibytes (受信) / ifi_obytes (送信) を読み取る
    ///
    /// - Returns: 読み取り結果
    /// - Throws: NET-001 (インターフェース不明)、NET-003 (読み取り失敗)
    func readCounters() throws -> WifiCounterSnapshot {
        let interfaceName = try getInterfaceName()

        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0 else {
            throw WifiCounterError.snapshotFailed(message: "getifaddrs() failed: errno=\(errno)")
        }
        defer { freeifaddrs(ifaddrPtr) }

        var ptr = ifaddrPtr
        while let ifaddr = ptr {
            let name = String(cString: ifaddr.pointee.ifa_name)

            if name == interfaceName,
               ifaddr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK),
               let data = ifaddr.pointee.ifa_data {
                let ifData = data.assumingMemoryBound(to: if_data.self).pointee
                return WifiCounterSnapshot(
                    interfaceName: interfaceName,
                    sentBytesTotal: Int64(ifData.ifi_obytes),
                    recvBytesTotal: Int64(ifData.ifi_ibytes)
                )
            }
            ptr = ifaddr.pointee.ifa_next
        }

        throw WifiCounterError.snapshotFailed(message: "No if_data found for interface \(interfaceName)")
    }

    /// Wi-Fi インターフェース名を取得する
    ///
    /// CWWiFiClient.shared().interface()?.interfaceName で動的に特定。
    /// en0 固定にしない。
    ///
    /// - Returns: インターフェース名 (例: "en0")
    /// - Throws: NET-001 (インターフェース不明)
    func getInterfaceName() throws -> String {
        guard let iface = CWWiFiClient.shared().interface(),
              let name = iface.interfaceName else {
            throw WifiCounterError.interfaceUnknown
        }
        return name
    }

    // MARK: - Types

    /// Wi-Fi カウンタスナップショット
    struct WifiCounterSnapshot: Sendable {
        /// インターフェース名
        let interfaceName: String

        /// 送信バイト数 (累積カウンタ値)
        let sentBytesTotal: Int64

        /// 受信バイト数 (累積カウンタ値)
        let recvBytesTotal: Int64
    }
}

// MARK: - Wi-Fi Counter Errors

enum WifiCounterError: Error, LocalizedError {
    case interfaceUnknown
    case snapshotFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .interfaceUnknown:
            return "NET-001: Wi-Fi interface not found"
        case .snapshotFailed(let msg):
            return "NET-003: Wi-Fi counter snapshot failed: \(msg)"
        }
    }
}
