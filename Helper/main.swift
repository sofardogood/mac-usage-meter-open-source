import Foundation
import Shared

/// Privileged Helper エントリポイント
///
/// LaunchDaemon として root 権限で動作する。
/// NSXPCListener(machServiceName:) で XPC リスナーを開始し、
/// UI App からの接続を受け付ける。
///
/// MachService 名: com.macusagemeter.helper
///
/// --local オプション:
///   署名なしでローカルテスト可能なモードで起動する。
///   launchd に MachService を一時登録し、
///   UI App から machServiceName ベースで接続可能にする。
///   DEBUG ビルド時のみ有効。

let isLocalMode = CommandLine.arguments.contains("--local")

if isLocalMode {
    XPCPeerValidator.localMode = true
}

let delegate = HelperDelegate()

let machServiceName = "com.macusagemeter.helper"

if isLocalMode {
    #if DEBUG
    print("[Helper] Starting in LOCAL mode (development testing)")
    print("[Helper] Mach service: \(machServiceName)")
    print("[Helper] Peer validation: SKIPPED (DEBUG build)")

    // ローカルモードでは machServiceName ベースのリスナーを使用する。
    // sudo で起動すれば launchd (system domain) に MachService が登録される。
    let listener = NSXPCListener(machServiceName: machServiceName)
    listener.delegate = delegate
    listener.resume()

    // sentinel ファイルを書き出して起動完了を通知する
    let sentinelPath = "/tmp/com.macusagemeter.helper.local.ready"
    FileManager.default.createFile(atPath: sentinelPath, contents: Data("ready".utf8))
    print("[Helper] Ready sentinel written to \(sentinelPath)")
    print("[Helper] Waiting for XPC connections...")

    // RunLoop を維持して Helper プロセスを存続させる
    RunLoop.current.run()
    #else
    print("[Helper] ERROR: --local mode is only available in DEBUG builds.")
    print("[Helper] Build with: swift build -c debug")
    exit(1)
    #endif
} else {
    // 通常モード: LaunchDaemon として machServiceName で起動
    let listener = NSXPCListener(machServiceName: machServiceName)
    listener.delegate = delegate
    listener.resume()

    // RunLoop を維持して Helper プロセスを存続させる
    RunLoop.current.run()
}
