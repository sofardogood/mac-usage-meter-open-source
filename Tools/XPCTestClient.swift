import Foundation
import Shared

// MARK: - XPC Test Client
//
// 開発用 XPC テストクライアント
// Helper を --local モードで起動し、全8コマンドの E2E テストを行う。
//
// 使い方:
//   1. ターミナル1: sudo swift run Helper --local
//   2. ターミナル2: swift run XPCTestClient

// MARK: - Configuration

let machServiceName = "com.macusagemeter.helper"

// MARK: - Test Runner

final class XPCTestRunner: NSObject {

    private var connection: NSXPCConnection?
    var passCount = 0
    var failCount = 0
    var skipCount = 0

    func run() {
        print("=== XPC Test Client ===")
        print("Connecting to Helper via machService: \(machServiceName)")
        print()

        let conn = NSXPCConnection(machServiceName: machServiceName, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)

        conn.interruptionHandler = {
            print("[WARN] XPC connection interrupted")
        }
        conn.invalidationHandler = {
            print("[WARN] XPC connection invalidated")
        }

        conn.resume()
        connection = conn
        print("[OK] Connected to Helper via machService")
        print()

        // テスト実行
        let group = DispatchGroup()

        let tests: [(String, (DispatchGroup) -> Void)] = [
            ("1. PING", testPing),
            ("2. GET_SERVICE_STATUS", testGetServiceStatus),
            ("3. GET_CAPABILITIES", testGetCapabilities),
            ("4. REQUEST_POWER_SAMPLE", testRequestPowerSample),
            ("5. REQUEST_WIFI_SNAPSHOT", testRequestWifiSnapshot),
            ("6. RELOAD_PRIVILEGE_STATE", testReloadPrivilegeState),
            ("7. COLLECT_HEALTH_REPORT", testCollectHealthReport),
            ("8. ROTATE_DEBUG_CAPTURE", testRotateDebugCapture),
        ]

        for (name, test) in tests {
            printHeader(name)
            group.enter()
            test(group)
            let waitResult = group.wait(timeout: .now() + 15)
            if waitResult == .timedOut {
                printResult(.fail, "Timed out after 15 seconds")
                failCount += 1
            }
            print()
        }

        // サマリー
        printSummary()

        // クリーンアップ
        conn.invalidate()
        connection = nil
    }

    // MARK: - Helper

    private func proxy() -> HelperProtocol? {
        guard let conn = connection else {
            print("  [ERROR] No connection")
            return nil
        }
        return conn.remoteObjectProxyWithErrorHandler { error in
            print("  [ERROR] Proxy error: \(error.localizedDescription)")
        } as? HelperProtocol
    }

    // MARK: - Tests

    func testPing(_ group: DispatchGroup) {
        guard let proxy = proxy() else {
            printResult(.fail, "No proxy")
            failCount += 1
            group.leave()
            return
        }

        proxy.ping { [self] result in
            if result {
                printResult(.pass, "ping returned true")
                passCount += 1
            } else {
                printResult(.fail, "ping returned false (expected true)")
                failCount += 1
            }
            group.leave()
        }
    }

    func testGetServiceStatus(_ group: DispatchGroup) {
        guard let proxy = proxy() else {
            printResult(.fail, "No proxy")
            failCount += 1
            group.leave()
            return
        }

        proxy.getServiceStatus { [self] data in
            do {
                let envelope = try JSONDecoder().decode(
                    XPCResponseEnvelope<ServiceStatusResponse>.self, from: data)
                if let resp = envelope.data {
                    print("  serviceState:    \(resp.serviceState.rawValue)")
                    print("  privilegeState:  \(resp.privilegeState.rawValue)")
                    print("  protocolVersion: \(resp.protocolVersion)")
                    print("  helperVersion:   \(resp.helperVersion)")
                    printResult(.pass, "envelope.result = \(envelope.result.rawValue)")
                    passCount += 1
                } else {
                    printResult(.fail, "data is nil, errorCode=\(envelope.errorCode ?? "none")")
                    failCount += 1
                }
            } catch {
                printResult(.fail, "Decode error: \(error.localizedDescription)")
                failCount += 1
            }
            group.leave()
        }
    }

    func testGetCapabilities(_ group: DispatchGroup) {
        guard let proxy = proxy() else {
            printResult(.fail, "No proxy")
            failCount += 1
            group.leave()
            return
        }

        proxy.getCapabilities { [self] data in
            do {
                let envelope = try JSONDecoder().decode(
                    XPCResponseEnvelope<CapabilitiesResponse>.self, from: data)
                if let resp = envelope.data {
                    print("  hardwareFamily:  \(resp.hardwareFamily.rawValue)")
                    print("  osMajorVersion:  \(resp.osMajorVersion)")
                    print("  profiles count:  \(resp.profiles.count)")
                    for p in resp.profiles {
                        print("    - \(p.profileId) (level=\(p.sourceLevel), keys=\(p.expectedMetricKeys))")
                    }
                    printResult(.pass, "envelope.result = \(envelope.result.rawValue)")
                    passCount += 1
                } else {
                    printResult(.fail, "data is nil, errorCode=\(envelope.errorCode ?? "none")")
                    failCount += 1
                }
            } catch {
                printResult(.fail, "Decode error: \(error.localizedDescription)")
                failCount += 1
            }
            group.leave()
        }
    }

    func testRequestPowerSample(_ group: DispatchGroup) {
        guard let proxy = proxy() else {
            printResult(.fail, "No proxy")
            failCount += 1
            group.leave()
            return
        }

        print("  (Note: powermetrics requires root; expecting success with sudo)")

        proxy.requestPowerSample(profileId: "default", timeoutSec: 8, collectDebugRaw: false) { [self] data in
            do {
                let envelope = try JSONDecoder().decode(
                    XPCResponseEnvelope<PowerSampleResponse>.self, from: data)
                if let resp = envelope.data {
                    print("  status:      \(resp.status)")
                    print("  sourceLevel: \(resp.sourceLevel)")
                    if let watts = resp.avgWatts {
                        print("  avgWatts:    \(watts)")
                    }
                    if let errorCode = resp.errorCode {
                        print("  errorCode:   \(errorCode)")
                    }
                    printResult(.pass, "status=\(resp.status)")
                    passCount += 1
                } else {
                    printResult(.fail, "data is nil, errorCode=\(envelope.errorCode ?? "none")")
                    failCount += 1
                }
            } catch {
                printResult(.fail, "Decode error: \(error.localizedDescription)")
                failCount += 1
            }
            group.leave()
        }
    }

    func testRequestWifiSnapshot(_ group: DispatchGroup) {
        guard let proxy = proxy() else {
            printResult(.fail, "No proxy")
            failCount += 1
            group.leave()
            return
        }

        proxy.requestWifiSnapshot { [self] data in
            do {
                let envelope = try JSONDecoder().decode(
                    XPCResponseEnvelope<WifiSnapshotResponse>.self, from: data)
                if let resp = envelope.data {
                    print("  status:         \(resp.status)")
                    if let iface = resp.interfaceName {
                        print("  interfaceName:  \(iface)")
                    }
                    if let sent = resp.sentBytesTotal {
                        print("  sentBytesTotal: \(sent)")
                    }
                    if let recv = resp.recvBytesTotal {
                        print("  recvBytesTotal: \(recv)")
                    }
                    printResult(.pass, "Wi-Fi snapshot: status=\(resp.status)")
                    passCount += 1
                } else {
                    printResult(.fail, "data is nil, errorCode=\(envelope.errorCode ?? "none")")
                    failCount += 1
                }
            } catch {
                printResult(.fail, "Decode error: \(error.localizedDescription)")
                failCount += 1
            }
            group.leave()
        }
    }

    func testReloadPrivilegeState(_ group: DispatchGroup) {
        guard let proxy = proxy() else {
            printResult(.fail, "No proxy")
            failCount += 1
            group.leave()
            return
        }

        proxy.reloadPrivilegeState { [self] data in
            do {
                let envelope = try JSONDecoder().decode(
                    XPCResponseEnvelope<PrivilegeStateResponse>.self, from: data)
                if let resp = envelope.data {
                    print("  privilegeState: \(resp.privilegeState)")
                    printResult(.pass, "envelope.result = \(envelope.result.rawValue)")
                    passCount += 1
                } else {
                    printResult(.fail, "data is nil, errorCode=\(envelope.errorCode ?? "none")")
                    failCount += 1
                }
            } catch {
                printResult(.fail, "Decode error: \(error.localizedDescription)")
                failCount += 1
            }
            group.leave()
        }
    }

    func testCollectHealthReport(_ group: DispatchGroup) {
        guard let proxy = proxy() else {
            printResult(.fail, "No proxy")
            failCount += 1
            group.leave()
            return
        }

        proxy.collectHealthReport { [self] data in
            do {
                let envelope = try JSONDecoder().decode(
                    XPCResponseEnvelope<HealthReportResponse>.self, from: data)
                if let resp = envelope.data {
                    print("  helperPid:    \(resp.helperPid)")
                    print("  uptimeSec:    \(resp.uptimeSec)")
                    print("  version:      \(resp.helperVersion)")
                    print("  powerSamples: \(resp.totalPowerSamples)")
                    print("  wifiSnaps:    \(resp.totalWifiSnapshots)")
                    print("  failures:     \(resp.consecutiveFailures)")
                    printResult(.pass, "envelope.result = \(envelope.result.rawValue)")
                    passCount += 1
                } else {
                    printResult(.fail, "data is nil, errorCode=\(envelope.errorCode ?? "none")")
                    failCount += 1
                }
            } catch {
                printResult(.fail, "Decode error: \(error.localizedDescription)")
                failCount += 1
            }
            group.leave()
        }
    }

    func testRotateDebugCapture(_ group: DispatchGroup) {
        guard let proxy = proxy() else {
            printResult(.fail, "No proxy")
            failCount += 1
            group.leave()
            return
        }

        proxy.rotateDebugCapture(enabled: true) { [self] data in
            do {
                let envelope = try JSONDecoder().decode(
                    XPCResponseEnvelope<DebugCaptureResponse>.self, from: data)
                if let resp = envelope.data {
                    print("  currentState: \(resp.currentState)")
                    if resp.currentState == true {
                        printResult(.pass, "Debug capture enabled successfully")
                        passCount += 1
                    } else {
                        printResult(.fail, "Expected currentState=true, got false")
                        failCount += 1
                    }
                } else {
                    printResult(.fail, "data is nil, errorCode=\(envelope.errorCode ?? "none")")
                    failCount += 1
                }
            } catch {
                printResult(.fail, "Decode error: \(error.localizedDescription)")
                failCount += 1
            }
            group.leave()
        }
    }

    // MARK: - Output Formatting

    enum TestResult: String {
        case pass = "PASS"
        case fail = "FAIL"
        case skip = "SKIP"
    }

    func printHeader(_ name: String) {
        print("--- \(name) ---")
    }

    func printResult(_ result: TestResult, _ detail: String) {
        let marker: String
        switch result {
        case .pass: marker = "[PASS]"
        case .fail: marker = "[FAIL]"
        case .skip: marker = "[SKIP]"
        }
        print("  \(marker) \(detail)")
    }

    func printSummary() {
        print("========================================")
        print("  Results: \(passCount) passed, \(failCount) failed, \(skipCount) skipped")
        print("  Total:   \(passCount + failCount + skipCount) / 8")
        print("========================================")
        if failCount > 0 {
            print("  Some tests FAILED.")
        } else {
            print("  All tests PASSED.")
        }
    }
}

// MARK: - Main

let runner = XPCTestRunner()
runner.run()

// RunLoop を少し回して残りの XPC コールバックを処理
RunLoop.current.run(until: Date(timeIntervalSinceNow: 1))

exit(runner.failCount > 0 ? 1 : 0)
