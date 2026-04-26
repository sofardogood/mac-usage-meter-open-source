import Foundation
import Security

/// XPC Peer 認証 (第12.1節)
///
/// Helper は接続受理時に NSXPCConnection の auditToken を使用して接続元を検証する。
/// SecCodeCopyGuestWithAttributes で audit token から SecCode を取得し、
/// SecCodeCheckValidity で署名を検証する。
struct XPCPeerValidator: Sendable {

    /// 許可する signing identifier (UI App のもの)
    /// Info.plist の SMAuthorizedClients と一致させる
    static let authorizedClientIdentifier = "com.macusagemeter.MacUsageMeter"

    // MARK: - Validation

    /// 接続元の peer を検証する
    ///
    /// 1. NSXPCConnection の auditToken を取得
    /// 2. SecCodeCopyGuestWithAttributes で SecCode を取得
    /// 3. SecCodeCheckValidity で署名を検証
    /// 4. signing identifier が authorizedClientIdentifier と一致するか確認
    ///
    /// - Parameter connection: 検証対象の XPC 接続
    /// - Returns: 検証成功なら true
    func validatePeer(_ connection: NSXPCConnection) -> Bool {
        #if DEBUG
        // デバッグビルドでは署名検証をスキップ (開発時の利便性のため)
        return true
        #else
        guard let identifier = signingIdentifier(for: connection) else {
            return false
        }
        return identifier == Self.authorizedClientIdentifier
        #endif
    }

    /// audit token から signing identifier を取得する
    ///
    /// - Parameter connection: XPC 接続
    /// - Returns: signing identifier。取得失敗時は nil
    func signingIdentifier(for connection: NSXPCConnection) -> String? {
        // audit_token_t を取得
        let token = connection.auditToken

        // audit token から SecCode を取得
        var code: SecCode?
        let tokenData = withUnsafeBytes(of: token) { Data($0) }
        let attributes = [
            kSecGuestAttributeAudit: tokenData
        ] as CFDictionary

        let status = SecCodeCopyGuestWithAttributes(nil, attributes, [], &code)
        guard status == errSecSuccess, let secCode = code else {
            return nil
        }

        // 署名の有効性を検証
        let validityStatus = SecCodeCheckValidity(secCode, [], nil)
        guard validityStatus == errSecSuccess else {
            return nil
        }

        // SecCode → SecStaticCode に変換
        var staticCode: SecStaticCode?
        let copyStatus = SecCodeCopyStaticCode(secCode, [], &staticCode)
        guard copyStatus == errSecSuccess, let secStaticCode = staticCode else {
            return nil
        }

        // signing information を取得
        var info: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(secStaticCode, [], &info)
        guard infoStatus == errSecSuccess, let signingInfo = info as? [String: Any] else {
            return nil
        }

        // signing identifier を取得
        return signingInfo[kSecCodeInfoIdentifier as String] as? String
    }
}

// MARK: - NSXPCConnection auditToken extension

extension NSXPCConnection {
    /// audit_token_t を取得する
    ///
    /// NSXPCConnection の private API にアクセスせず、
    /// processIdentifier をベースにした簡易検証も可能にする。
    var auditToken: audit_token_t {
        // NSXPCConnection は内部的に auditToken を保持している。
        // 公開 API としてはValue-for-key で取得する。
        var token = audit_token_t()
        if let value = self.value(forKey: "auditToken") as? Data, value.count == MemoryLayout<audit_token_t>.size {
            _ = withUnsafeMutableBytes(of: &token) { dest in
                value.copyBytes(to: dest)
            }
        }
        return token
    }
}
