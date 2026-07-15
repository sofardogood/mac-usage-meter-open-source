import Foundation

/// `nettop` の接続別カウンタを読み、アプリ名と接続先ホストに帰属させる。
/// HTTPS の内容は復号しないため、表示する「サイト」は接続先ホスト名（CDN を含む）。
struct ProcessNetworkUsageReader: Sendable {
    struct Flow: Sendable {
        let key: String
        let applicationName: String
        let destinationHost: String
        let receivedBytesTotal: Int64
        let sentBytesTotal: Int64
    }

    func readFlows() throws -> [Flow] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = ["-t", "external", "-L", "1", "-x"]
        process.environment = [:]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var applicationName: String?
        var flows: [Flow] = []
        var duplicateCounts: [String: Int] = [:]

        for line in text.split(whereSeparator: \ .isNewline).dropFirst() {
            let columns = line.split(separator: ",", omittingEmptySubsequences: false)
            guard columns.count >= 7 else { continue }
            let label = String(columns[1])
            if let app = processName(from: label) {
                applicationName = app
                continue
            }
            guard let app = applicationName,
                  label.contains("<->"),
                  let received = Int64(columns[4]),
                  let sent = Int64(columns[5]) else { continue }
            let host = destinationHost(from: label)
            let baseKey = "\(app)|\(label)"
            let occurrence = duplicateCounts[baseKey, default: 0]
            duplicateCounts[baseKey] = occurrence + 1
            let key = "\(baseKey)|\(occurrence)"
            flows.append(Flow(key: key, applicationName: app, destinationHost: host,
                              receivedBytesTotal: received, sentBytesTotal: sent))
        }
        return flows
    }

    private func processName(from label: String) -> String? {
        guard !label.contains("<->"),
              let dot = label.lastIndex(of: "."),
              label[label.index(after: dot)...].allSatisfy(\.isNumber) else { return nil }
        return String(label[..<dot])
    }

    private func destinationHost(from label: String) -> String {
        guard let separator = label.range(of: "<->") else { return "その他の接続" }
        let remote = String(label[separator.upperBound...])
        // nettop は IPv6 のポートを `host.port`、IPv4/名前解決済みホストを
        // `host:port` と出力する。
        if let dot = remote.lastIndex(of: "."),
           remote[remote.index(after: dot)...].allSatisfy(\.isNumber) {
            return String(remote[..<dot])
        }
        if let colon = remote.lastIndex(of: ":") { return String(remote[..<colon]) }
        return remote
    }
}
