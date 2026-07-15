import Foundation

/// 利用先に帰属した通信量の 1 サンプル。
///
/// `NetworkExtension` が観測したフローを保存するための境界モデル。送受信量は
/// 実測値、`estimatedWatts` は同じ時刻の Mac 全体の実測電力を活動量で配分した
/// 推定値であり、アプリ単体を直接計測した値ではない。
struct AttributedUsage: Codable, Sendable, Identifiable {
    let id: Int64?
    let capturedAtMs: Int64
    let applicationName: String
    let bundleIdentifier: String?
    let destinationHost: String?
    let sentBytes: Int64
    let receivedBytes: Int64
    let estimatedWatts: Double?

    var totalBytes: Int64 { sentBytes + receivedBytes }
    var destinationLabel: String { destinationHost ?? "その他の接続" }
}

/// 詳細画面に表示する、利用先単位の集計値。
struct UsageDestinationSummary: Sendable, Identifiable {
    let applicationName: String
    let bundleIdentifier: String?
    let destinationHost: String?
    let totalBytes: Int64
    let estimatedWatts: Double?

    var id: String { "\(bundleIdentifier ?? applicationName)|\(destinationHost ?? "")" }
    var destinationLabel: String { destinationHost ?? "その他の接続" }
}
