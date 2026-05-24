import Foundation
@preconcurrency import Security

/// XPC Peer 認証 (第12.1節)
///
/// Helper は接続受理時に NSXPCConnection の auditToken を使用して接続元を検証する。
/// 接続元の bundle identifier だけでなく、Helper 自身と同じ Team ID で署名されていることも確認する。
struct XPCPeerValidator: Sendable {

    /// 許可する signing identifier (UI App のもの)
    /// Info.plist の SMAuthorizedClients と一致させる
    static let authorizedClientIdentifier = "com.macusagemeter.MacUsageMeter"

    /// 開発時に未署名/adhoc の peer を許可するための明示的な opt-in。
    /// DEBUG ビルドでもデフォルトでは署名検証を迂回しない。
    private static let allowUnverifiedDebugPeersEnv = "MAC_USAGE_METER_ALLOW_UNVERIFIED_XPC"

    // MARK: - Validation

    /// 接続元の peer を検証する。
    ///
    /// 1. audit token から peer の SecCode を取得
    /// 2. SecCodeCheckValidity で署名を検証
    /// 3. signing identifier が authorizedClientIdentifier と一致するか確認
    /// 4. peer の Team ID が Helper 自身の Team ID と一致するか確認
    func validatePeer(_ connection: NSXPCConnection) -> Bool {
        guard let peer = signingInfo(for: connection) else {
            #if DEBUG
            return Self.debugAllowsUnverifiedPeers
            #else
            return false
            #endif
        }

        guard peer.identifier == Self.authorizedClientIdentifier else {
            return false
        }

        guard let helperTeamIdentifier = Self.currentExecutableTeamIdentifier,
              let peerTeamIdentifier = peer.teamIdentifier,
              peerTeamIdentifier == helperTeamIdentifier else {
            #if DEBUG
            return Self.debugAllowsUnverifiedPeers
            #else
            return false
            #endif
        }

        return true
    }

    private static var debugAllowsUnverifiedPeers: Bool {
        ProcessInfo.processInfo.environment[allowUnverifiedDebugPeersEnv] == "1"
    }

    /// 現在実行中の Helper 自身の Team ID。App と Helper が同一 Team で署名されていることを確認する。
    private static var currentExecutableTeamIdentifier: String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }

        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let signingInfo = info as? [String: Any] else {
            return nil
        }

        return signingInfo[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// 後方互換のため signing identifier のみを返す。
    func signingIdentifier(for connection: NSXPCConnection) -> String? {
        signingInfo(for: connection)?.identifier
    }

    /// audit token から署名情報を取得する。
    func signingInfo(for connection: NSXPCConnection) -> PeerSigningInfo? {
        guard let signingInfo = rawSigningInformation(for: connection) else {
            return nil
        }

        guard let identifier = signingInfo[kSecCodeInfoIdentifier as String] as? String else {
            return nil
        }

        return PeerSigningInfo(
            identifier: identifier,
            teamIdentifier: signingInfo[kSecCodeInfoTeamIdentifier as String] as? String
        )
    }

    struct PeerSigningInfo: Sendable {
        let identifier: String
        let teamIdentifier: String?
    }

    private func rawSigningInformation(for connection: NSXPCConnection) -> [String: Any]? {
        let token = connection.auditToken

        var code: SecCode?
        let tokenData = withUnsafeBytes(of: token) { Data($0) }
        let attributes = [kSecGuestAttributeAudit: tokenData] as CFDictionary

        let status = SecCodeCopyGuestWithAttributes(nil, attributes, [], &code)
        guard status == errSecSuccess, let secCode = code else {
            return nil
        }

        let validityStatus = SecCodeCheckValidity(secCode, [], nil)
        guard validityStatus == errSecSuccess else {
            return nil
        }

        var staticCode: SecStaticCode?
        let copyStatus = SecCodeCopyStaticCode(secCode, [], &staticCode)
        guard copyStatus == errSecSuccess, let secStaticCode = staticCode else {
            return nil
        }

        var info: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(secStaticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        guard infoStatus == errSecSuccess, let signingInfo = info as? [String: Any] else {
            return nil
        }

        return signingInfo
    }
}

// MARK: - NSXPCConnection auditToken extension

extension NSXPCConnection {
    /// audit_token_t を取得する
    ///
    /// NSXPCConnection は public API として audit token を公開していないため、
    /// macOS の NSXPCConnection が保持する KVC プロパティから取得する。
    var auditToken: audit_token_t {
        var token = audit_token_t()
        if let value = self.value(forKey: "auditToken") as? Data,
           value.count == MemoryLayout<audit_token_t>.size {
            _ = withUnsafeMutableBytes(of: &token) { dest in
                value.copyBytes(to: dest)
            }
        }
        return token
    }
}
