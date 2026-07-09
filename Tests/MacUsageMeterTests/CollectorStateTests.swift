import XCTest
@testable import MacUsageMeter

/// Collector 状態遷移の単体テスト (第2.5節)
///
/// 観点: 状態遷移表に基づく全遷移パスの検証
/// 全遷移パス:
///   starting → normal (capabilitiesReady)
///   starting → limitedReady (capabilitiesLimited)
///   starting → limitedReady (helperUnavailable)
///   normal → degraded (consecutiveFailures: 3連続失敗)
///   degraded → normal (sampleSuccess: 成功1件)
///   degraded → limitedReady (profileVerificationFailed: 10連続失敗)
///   notReady → starting (privilegeGranted: 権限付与)
///   limitedReady → starting (privilegeGranted: 権限付与)
final class CollectorStateTests: XCTestCase {

    // MARK: - Starting → Normal

    /// starting + capabilitiesReady → normal
    /// 条件: GET_CAPABILITIES で power profile >= 1 件かつ Wi-Fi OK
    func test_starting_capabilitiesReady_transitionsToNormal() {
        let state = CollectorState.starting
        let next = state.transition(on: .capabilitiesReady)
        XCTAssertEqual(next, .normal)
    }

    // MARK: - Starting → Limited Ready

    /// starting + capabilitiesLimited → limited-ready
    /// 条件: Wi-Fi OK だが power profile = 0 件
    func test_starting_capabilitiesLimited_transitionsToLimitedReady() {
        let state = CollectorState.starting
        let next = state.transition(on: .capabilitiesLimited)
        XCTAssertEqual(next, .limitedReady)
    }

    // MARK: - Starting → Limited Ready (Helper unavailable)

    /// starting + helperUnavailable → limited-ready
    /// 条件: Helper 未登録 / 権限拒否 (Wi-Fi はローカルで計測可能)
    func test_starting_helperUnavailable_transitionsToLimitedReady() {
        let state = CollectorState.starting
        let next = state.transition(on: .helperUnavailable)
        XCTAssertEqual(next, .limitedReady)
    }

    // MARK: - Normal → Degraded

    /// normal + consecutiveFailures → degraded
    /// 条件: 電力サンプル 3 連続失敗
    func test_normal_consecutiveFailures_transitionsToDegraded() {
        let state = CollectorState.normal
        let next = state.transition(on: .consecutiveFailures)
        XCTAssertEqual(next, .degraded)
    }

    // MARK: - Degraded → Normal

    /// degraded + sampleSuccess → normal
    /// 条件: 成功サンプル 1 件取得
    func test_degraded_sampleSuccess_transitionsToNormal() {
        let state = CollectorState.degraded
        let next = state.transition(on: .sampleSuccess)
        XCTAssertEqual(next, .normal)
    }

    // MARK: - Degraded → Limited Ready

    /// degraded + profileVerificationFailed → limited-ready
    /// 条件: 10 連続失敗かつ profile 再検証で 0 件
    func test_degraded_profileVerificationFailed_transitionsToLimitedReady() {
        let state = CollectorState.degraded
        let next = state.transition(on: .profileVerificationFailed)
        XCTAssertEqual(next, .limitedReady)
    }

    // MARK: - Not Ready → Starting

    /// not-ready + privilegeGranted → starting
    /// 条件: 権限付与 / Helper 再登録成功
    func test_notReady_privilegeGranted_transitionsToStarting() {
        let state = CollectorState.notReady
        let next = state.transition(on: .privilegeGranted)
        XCTAssertEqual(next, .starting)
    }

    // MARK: - Limited Ready → Starting

    /// limited-ready + privilegeGranted → starting
    /// 条件: 権限付与 / Helper 再登録成功
    func test_limitedReady_privilegeGranted_transitionsToStarting() {
        let state = CollectorState.limitedReady
        let next = state.transition(on: .privilegeGranted)
        XCTAssertEqual(next, .starting)
    }

    // MARK: - Invalid Transitions (遷移不可のケースは nil を返す)

    /// normal + capabilitiesReady → nil (starting でしか起きない)
    func test_normal_capabilitiesReady_noTransition() {
        let state = CollectorState.normal
        let next = state.transition(on: .capabilitiesReady)
        XCTAssertNil(next)
    }

    /// normal + capabilitiesLimited → nil
    func test_normal_capabilitiesLimited_noTransition() {
        let state = CollectorState.normal
        let next = state.transition(on: .capabilitiesLimited)
        XCTAssertNil(next)
    }

    /// normal + helperUnavailable → limited-ready
    func test_normal_helperUnavailable_transitionsToLimitedReady() {
        let state = CollectorState.normal
        let next = state.transition(on: .helperUnavailable)
        XCTAssertEqual(next, .limitedReady)
    }

    /// normal + sampleSuccess → nil (degraded でしか起きない)
    func test_normal_sampleSuccess_noTransition() {
        let state = CollectorState.normal
        let next = state.transition(on: .sampleSuccess)
        XCTAssertNil(next)
    }

    /// normal + profileVerificationFailed → nil
    func test_normal_profileVerificationFailed_noTransition() {
        let state = CollectorState.normal
        let next = state.transition(on: .profileVerificationFailed)
        XCTAssertNil(next)
    }

    /// normal + privilegeGranted → nil
    func test_normal_privilegeGranted_noTransition() {
        let state = CollectorState.normal
        let next = state.transition(on: .privilegeGranted)
        XCTAssertNil(next)
    }

    /// limited-ready + sampleSuccess → nil (遷移不可)
    func test_limitedReady_sampleSuccess_noTransition() {
        let state = CollectorState.limitedReady
        let next = state.transition(on: .sampleSuccess)
        XCTAssertNil(next)
    }

    /// limited-ready + consecutiveFailures → nil
    func test_limitedReady_consecutiveFailures_noTransition() {
        let state = CollectorState.limitedReady
        let next = state.transition(on: .consecutiveFailures)
        XCTAssertNil(next)
    }

    /// starting + sampleSuccess → nil (starting では sampleSuccess は遷移なし)
    func test_starting_sampleSuccess_noTransition() {
        let state = CollectorState.starting
        let next = state.transition(on: .sampleSuccess)
        XCTAssertNil(next)
    }

    /// starting + consecutiveFailures → nil
    func test_starting_consecutiveFailures_noTransition() {
        let state = CollectorState.starting
        let next = state.transition(on: .consecutiveFailures)
        XCTAssertNil(next)
    }

    /// notReady + capabilitiesReady → nil (starting を経由する必要がある)
    func test_notReady_capabilitiesReady_noTransition() {
        let state = CollectorState.notReady
        let next = state.transition(on: .capabilitiesReady)
        XCTAssertNil(next)
    }

    /// notReady + consecutiveFailures → nil
    func test_notReady_consecutiveFailures_noTransition() {
        let state = CollectorState.notReady
        let next = state.transition(on: .consecutiveFailures)
        XCTAssertNil(next)
    }

    /// degraded + capabilitiesReady → nil
    func test_degraded_capabilitiesReady_noTransition() {
        let state = CollectorState.degraded
        let next = state.transition(on: .capabilitiesReady)
        XCTAssertNil(next)
    }

    /// degraded + helperUnavailable → limited-ready
    func test_degraded_helperUnavailable_transitionsToLimitedReady() {
        let state = CollectorState.degraded
        let next = state.transition(on: .helperUnavailable)
        XCTAssertEqual(next, .limitedReady)
    }

    // MARK: - Raw Value Encoding

    /// CollectorState の rawValue が期待通りであること
    func test_rawValues_matchExpected() {
        XCTAssertEqual(CollectorState.starting.rawValue, "starting")
        XCTAssertEqual(CollectorState.normal.rawValue, "normal")
        XCTAssertEqual(CollectorState.degraded.rawValue, "degraded")
        XCTAssertEqual(CollectorState.limitedReady.rawValue, "limited-ready")
        XCTAssertEqual(CollectorState.notReady.rawValue, "not-ready")
    }

    // MARK: - Full Transition Path Tests

    /// 正常フロー: starting → normal → degraded → normal
    func test_fullPath_startingNormalDegradedNormal() {
        var state = CollectorState.starting

        // starting → normal
        guard let s1 = state.transition(on: .capabilitiesReady) else {
            return XCTFail("Expected transition to normal")
        }
        state = s1
        XCTAssertEqual(state, .normal)

        // normal → degraded
        guard let s2 = state.transition(on: .consecutiveFailures) else {
            return XCTFail("Expected transition to degraded")
        }
        state = s2
        XCTAssertEqual(state, .degraded)

        // degraded → normal
        guard let s3 = state.transition(on: .sampleSuccess) else {
            return XCTFail("Expected transition to normal")
        }
        state = s3
        XCTAssertEqual(state, .normal)
    }

    /// 縮退フロー: starting → normal → degraded → limitedReady
    func test_fullPath_startingNormalDegradedLimitedReady() {
        var state = CollectorState.starting

        guard let s1 = state.transition(on: .capabilitiesReady) else {
            return XCTFail("Expected transition to normal")
        }
        state = s1

        guard let s2 = state.transition(on: .consecutiveFailures) else {
            return XCTFail("Expected transition to degraded")
        }
        state = s2

        guard let s3 = state.transition(on: .profileVerificationFailed) else {
            return XCTFail("Expected transition to limitedReady")
        }
        state = s3
        XCTAssertEqual(state, .limitedReady)
    }

    /// 権限回復フロー: starting → limitedReady → starting → normal
    func test_fullPath_startingLimitedReadyStartingNormal() {
        var state = CollectorState.starting

        guard let s1 = state.transition(on: .helperUnavailable) else {
            return XCTFail("Expected transition to limitedReady")
        }
        state = s1
        XCTAssertEqual(state, .limitedReady)

        guard let s2 = state.transition(on: .privilegeGranted) else {
            return XCTFail("Expected transition to starting")
        }
        state = s2
        XCTAssertEqual(state, .starting)

        guard let s3 = state.transition(on: .capabilitiesReady) else {
            return XCTFail("Expected transition to normal")
        }
        state = s3
        XCTAssertEqual(state, .normal)
    }
}
