import Foundation

/// Collector Controller の状態マシン (第2.5節)
///
/// Collector の動作状態を表現し、遷移条件を管理する。
enum CollectorState: String, Codable, Sendable {
    /// 起動中: GET_CAPABILITIES 完了待ち
    case starting

    /// 通常動作: 電力・Wi-Fi ともに採取可能
    case normal

    /// 縮退動作: 電力サンプル3連続失敗
    case degraded

    /// 限定準備完了: Wi-Fi は可能だが電力は不可
    case limitedReady = "limited-ready"

    /// 未準備: Helper 未登録 / 権限なし
    case notReady = "not-ready"

    // MARK: - Transition Logic

    /// 遷移可能な状態を返す
    ///
    /// - Parameter event: 発生したイベント
    /// - Returns: 遷移先の状態。遷移不可の場合は nil
    func transition(on event: CollectorEvent) -> CollectorState? {
        switch (self, event) {
        // starting → normal: GET_CAPABILITIES で power profile >= 1 件かつ Wi-Fi OK
        case (.starting, .capabilitiesReady):
            return .normal

        // starting → limited-ready: Wi-Fi OK だが power profile = 0 件
        case (.starting, .capabilitiesLimited):
            return .limitedReady

        // starting → limited-ready: Helper 未登録 / 権限拒否 (Wi-Fi はローカルで計測可能)
        case (.starting, .helperUnavailable):
            return .limitedReady

        // normal → degraded: 電力サンプル 3 連続失敗
        case (.normal, .consecutiveFailures):
            return .degraded

        // degraded → normal: 成功サンプル 1 件取得
        case (.degraded, .sampleSuccess):
            return .normal

        // normal/degraded → limited-ready: Helper 切断 / 権限拒否
        case (.normal, .helperUnavailable), (.degraded, .helperUnavailable):
            return .limitedReady

        // degraded → limited-ready: 10 連続失敗かつ profile 再検証で 0 件
        case (.degraded, .profileVerificationFailed):
            return .limitedReady

        // not-ready → starting: 権限付与 / Helper 再登録成功
        case (.notReady, .privilegeGranted):
            return .starting

        // limited-ready → starting: 権限付与 / Helper 再登録成功
        case (.limitedReady, .privilegeGranted):
            return .starting

        default:
            return nil
        }
    }
}

/// Collector に発生するイベント
enum CollectorEvent: Sendable {
    /// GET_CAPABILITIES で power profile >= 1 件かつ Wi-Fi OK
    case capabilitiesReady

    /// Wi-Fi OK だが power profile = 0 件
    case capabilitiesLimited

    /// Helper 未登録 / 権限拒否
    case helperUnavailable

    /// 電力サンプル 3 連続失敗
    case consecutiveFailures

    /// 成功サンプル 1 件取得
    case sampleSuccess

    /// 10 連続失敗かつ profile 再検証で 0 件
    case profileVerificationFailed

    /// 権限付与 / Helper 再登録成功
    case privilegeGranted
}
