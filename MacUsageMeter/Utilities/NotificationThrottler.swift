import Foundation

/// 通知重複抑止 (第13.2節)
///
/// 同一 state_code の通知は、前回通知から 30 分以上経過するまで再送しない。
actor NotificationThrottler {

    /// 抑止間隔 (秒)
    static let throttleIntervalSeconds: TimeInterval = 1800 // 30分

    /// 最終通知時刻の記録 (state_code -> 最終通知時刻)
    private var lastNotifiedAt: [String: Date] = [:]

    // MARK: - Throttle Check

    /// 通知を送信してよいか判定する
    ///
    /// 同一 state_code の前回通知から 30 分以上経過していれば true。
    ///
    /// - Parameter stateCode: 状態コード
    /// - Returns: 送信可能なら true
    func shouldNotify(for stateCode: StateCode) -> Bool {
        let key = stateCode.rawValue
        guard let lastTime = lastNotifiedAt[key] else {
            return true
        }
        return Date().timeIntervalSince(lastTime) >= Self.throttleIntervalSeconds
    }

    /// 通知送信を記録する
    ///
    /// - Parameter stateCode: 通知した状態コード
    func recordNotification(for stateCode: StateCode) {
        lastNotifiedAt[stateCode.rawValue] = Date()
    }

    /// 特定の状態コードの抑止をリセットする
    ///
    /// 状態が回復した場合に呼び出す。
    ///
    /// - Parameter stateCode: リセットする状態コード
    func resetThrottle(for stateCode: StateCode) {
        lastNotifiedAt.removeValue(forKey: stateCode.rawValue)
    }

    /// 全ての抑止をリセットする
    func resetAll() {
        lastNotifiedAt.removeAll()
    }
}
