import XCTest
@testable import MacUsageMeter

/// 通知重複抑止の単体テスト (第13.2節)
///
/// 観点: 初回通知許可、30分以内の抑止、30分経過後の再許可、リセット
final class NotificationThrottlerTests: XCTestCase {

    // MARK: - Initial State

    /// 初回は通知を許可する
    func test_shouldNotify_firstTime_true() async {
        let throttler = NotificationThrottler()
        let result = await throttler.shouldNotify(for: .powerDataFailure)
        XCTAssertTrue(result)
    }

    // MARK: - After Recording

    /// 記録直後は同一コードの通知を抑止する
    func test_shouldNotify_afterRecord_false() async {
        let throttler = NotificationThrottler()
        await throttler.recordNotification(for: .powerDataFailure)
        let result = await throttler.shouldNotify(for: .powerDataFailure)
        XCTAssertFalse(result)
    }

    /// 異なるコードは影響を受けない
    func test_shouldNotify_differentCode_true() async {
        let throttler = NotificationThrottler()
        await throttler.recordNotification(for: .powerDataFailure)
        let result = await throttler.shouldNotify(for: .databaseFailure)
        XCTAssertTrue(result)
    }

    // MARK: - Reset

    /// 個別リセット: 特定のコードのみリセットされる
    func test_resetThrottle_specificCode_onlyThatCodeReset() async {
        let throttler = NotificationThrottler()
        await throttler.recordNotification(for: .powerDataFailure)
        await throttler.recordNotification(for: .databaseFailure)

        await throttler.resetThrottle(for: .powerDataFailure)

        let powerResult = await throttler.shouldNotify(for: .powerDataFailure)
        let dbResult = await throttler.shouldNotify(for: .databaseFailure)
        XCTAssertTrue(powerResult, "Reset code should be notifiable")
        XCTAssertFalse(dbResult, "Other code should still be throttled")
    }

    /// 全リセット: 全てのコードがリセットされる
    func test_resetAll_allCodesReset() async {
        let throttler = NotificationThrottler()
        await throttler.recordNotification(for: .powerDataFailure)
        await throttler.recordNotification(for: .databaseFailure)
        await throttler.recordNotification(for: .wifiInterfaceUnknown)

        await throttler.resetAll()

        let r1 = await throttler.shouldNotify(for: .powerDataFailure)
        let r2 = await throttler.shouldNotify(for: .databaseFailure)
        let r3 = await throttler.shouldNotify(for: .wifiInterfaceUnknown)
        XCTAssertTrue(r1)
        XCTAssertTrue(r2)
        XCTAssertTrue(r3)
    }

    // MARK: - Throttle Interval

    /// 抑止間隔が 1800 秒 (30分) であること
    func test_throttleInterval_is1800Seconds() {
        XCTAssertEqual(NotificationThrottler.throttleIntervalSeconds, 1800)
    }

    // MARK: - Multiple Codes Independent

    /// 複数コードが独立して管理されること
    func test_multipleCodes_independent() async {
        let throttler = NotificationThrottler()

        // Record two codes
        await throttler.recordNotification(for: .authNotGranted)
        await throttler.recordNotification(for: .helperNotRegistered)

        // Both should be throttled
        let r1 = await throttler.shouldNotify(for: .authNotGranted)
        let r2 = await throttler.shouldNotify(for: .helperNotRegistered)
        XCTAssertFalse(r1)
        XCTAssertFalse(r2)

        // Unrecorded code should be allowed
        let r3 = await throttler.shouldNotify(for: .initialDataPending)
        XCTAssertTrue(r3)
    }
}
