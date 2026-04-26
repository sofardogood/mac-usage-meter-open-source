import XCTest
@testable import MacUsageMeter

/// 状態コードの単体テスト (第6章)
///
/// 観点: 全コードの存在、severity/retryable/scope の正確性、優先順位
final class StateCodeTests: XCTestCase {

    // MARK: - Completeness (M-001〜M-009 の全コード存在)

    /// 全9コード (M-001〜M-009) が定義されていること
    func test_allCodes_nineCodesExist() {
        XCTAssertEqual(StateCode.allCases.count, 9)
    }

    /// rawValue が M-001〜M-009 であること
    func test_rawValues_allExpectedCodesPresent() {
        let expectedCodes = ["M-001", "M-002", "M-003", "M-004", "M-005",
                             "M-006", "M-007", "M-008", "M-009"]
        let actualCodes = StateCode.allCases.map(\.rawValue).sorted()
        XCTAssertEqual(actualCodes, expectedCodes.sorted())
    }

    /// 各コードが正しい case にマッピングされること
    func test_rawValues_correctCaseMapping() {
        XCTAssertEqual(StateCode.authNotGranted.rawValue, "M-001")
        XCTAssertEqual(StateCode.helperNotRegistered.rawValue, "M-002")
        XCTAssertEqual(StateCode.powerMetricsUnsupported.rawValue, "M-003")
        XCTAssertEqual(StateCode.initialDataPending.rawValue, "M-004")
        XCTAssertEqual(StateCode.powerDataFailure.rawValue, "M-005")
        XCTAssertEqual(StateCode.wifiInterfaceUnknown.rawValue, "M-006")
        XCTAssertEqual(StateCode.staleContinued.rawValue, "M-007")
        XCTAssertEqual(StateCode.databaseFailure.rawValue, "M-008")
        XCTAssertEqual(StateCode.wifiDisconnected.rawValue, "M-009")
    }

    // MARK: - Severity の正しさ

    /// fatal: M-001 (権限未付与), M-002 (Helper未登録), M-008 (DB障害)
    func test_severity_fatalCodes_correctSeverity() {
        XCTAssertEqual(StateCode.authNotGranted.severity, .fatal)
        XCTAssertEqual(StateCode.helperNotRegistered.severity, .fatal)
        XCTAssertEqual(StateCode.databaseFailure.severity, .fatal)
    }

    /// degraded: M-003 (非対応), M-005 (解析失敗), M-006 (Wi-Fi IF不明), M-007 (stale)
    func test_severity_degradedCodes_correctSeverity() {
        XCTAssertEqual(StateCode.powerMetricsUnsupported.severity, .degraded)
        XCTAssertEqual(StateCode.powerDataFailure.severity, .degraded)
        XCTAssertEqual(StateCode.wifiInterfaceUnknown.severity, .degraded)
        XCTAssertEqual(StateCode.staleContinued.severity, .degraded)
    }

    /// informational: M-004 (取得待ち), M-009 (Wi-Fi未接続)
    func test_severity_informationalCodes_correctSeverity() {
        XCTAssertEqual(StateCode.initialDataPending.severity, .informational)
        XCTAssertEqual(StateCode.wifiDisconnected.severity, .informational)
    }

    /// 全コードに severity が設定されていること (網羅性チェック)
    func test_severity_allCodesHaveSeverity() {
        for code in StateCode.allCases {
            // severity は enum なので nil にはならないが、列挙の網羅性を確認
            let severity = code.severity
            XCTAssertTrue(
                severity == .fatal || severity == .degraded || severity == .informational,
                "\(code.rawValue) has unexpected severity: \(severity)"
            )
        }
    }

    // MARK: - Retryable フラグの正しさ

    /// retryable=true: M-002, M-005, M-006, M-007, M-008
    func test_retryable_trueCodes_correctFlag() {
        XCTAssertTrue(StateCode.helperNotRegistered.isRetryable)
        XCTAssertTrue(StateCode.powerDataFailure.isRetryable)
        XCTAssertTrue(StateCode.wifiInterfaceUnknown.isRetryable)
        XCTAssertTrue(StateCode.staleContinued.isRetryable)
        XCTAssertTrue(StateCode.databaseFailure.isRetryable)
    }

    /// retryable=false: M-001, M-003, M-004, M-009
    func test_retryable_falseCodes_correctFlag() {
        XCTAssertFalse(StateCode.authNotGranted.isRetryable)
        XCTAssertFalse(StateCode.powerMetricsUnsupported.isRetryable)
        XCTAssertFalse(StateCode.initialDataPending.isRetryable)
        XCTAssertFalse(StateCode.wifiDisconnected.isRetryable)
    }

    /// retryable フラグの網羅性: 全コードが true/false のいずれか
    func test_retryable_allCodesChecked() {
        let retryableCodes = StateCode.allCases.filter(\.isRetryable)
        let nonRetryableCodes = StateCode.allCases.filter { !$0.isRetryable }
        XCTAssertEqual(retryableCodes.count, 5, "5 codes should be retryable")
        XCTAssertEqual(nonRetryableCodes.count, 4, "4 codes should be non-retryable")
    }

    // MARK: - 優先順位の正しさ (6.2)
    // M-008 > M-001/M-002 > M-003/M-005 > M-007/M-006 > M-009 > M-004

    /// M-008 (DB障害) が最高優先度 (priority=1)
    func test_priority_databaseFailure_highest() {
        XCTAssertEqual(StateCode.databaseFailure.priority, 1)
    }

    /// M-001 (権限未付与) と M-002 (Helper未登録) が優先度2
    func test_priority_authAndHelper_secondHighest() {
        XCTAssertEqual(StateCode.authNotGranted.priority, 2)
        XCTAssertEqual(StateCode.helperNotRegistered.priority, 2)
    }

    /// M-003 (非対応) と M-005 (解析失敗) が優先度3
    func test_priority_unsupportedAndFailure_thirdHighest() {
        XCTAssertEqual(StateCode.powerMetricsUnsupported.priority, 3)
        XCTAssertEqual(StateCode.powerDataFailure.priority, 3)
    }

    /// M-007 (stale) と M-006 (Wi-Fi IF不明) が優先度4
    func test_priority_staleAndWifiUnknown_fourthHighest() {
        XCTAssertEqual(StateCode.staleContinued.priority, 4)
        XCTAssertEqual(StateCode.wifiInterfaceUnknown.priority, 4)
    }

    /// M-009 (Wi-Fi未接続) が優先度5
    func test_priority_wifiDisconnected_fifthHighest() {
        XCTAssertEqual(StateCode.wifiDisconnected.priority, 5)
    }

    /// M-004 (取得待ち) が最低優先度 (priority=6)
    func test_priority_initialDataPending_lowest() {
        XCTAssertEqual(StateCode.initialDataPending.priority, 6)
    }

    /// 優先順位の全体順序が仕様通りであること
    func test_priority_fullOrder_matchesSpec() {
        let sorted = StateCode.allCases.sorted { $0.priority < $1.priority }

        // priority 1: M-008
        XCTAssertEqual(sorted[0], .databaseFailure)

        // priority 2: M-001, M-002 (順序不問)
        let priority2 = sorted.filter { $0.priority == 2 }
        XCTAssertEqual(Set(priority2), Set([.authNotGranted, .helperNotRegistered]))

        // priority 3: M-003, M-005
        let priority3 = sorted.filter { $0.priority == 3 }
        XCTAssertEqual(Set(priority3), Set([.powerMetricsUnsupported, .powerDataFailure]))

        // priority 4: M-007, M-006
        let priority4 = sorted.filter { $0.priority == 4 }
        XCTAssertEqual(Set(priority4), Set([.staleContinued, .wifiInterfaceUnknown]))

        // priority 5: M-009
        let priority5 = sorted.filter { $0.priority == 5 }
        XCTAssertEqual(priority5, [.wifiDisconnected])

        // priority 6: M-004
        let priority6 = sorted.filter { $0.priority == 6 }
        XCTAssertEqual(priority6, [.initialDataPending])
    }

    /// 優先度順にソートできること: 先頭が M-008、末尾が M-004
    func test_priority_sorting_highestToLowest() {
        let sorted = StateCode.allCases.sorted { $0.priority < $1.priority }
        XCTAssertEqual(sorted.first, .databaseFailure)
        XCTAssertEqual(sorted.last, .initialDataPending)
    }

    // MARK: - User Message (ユーザー向け文言)

    /// 全コードにユーザー向け文言が設定されていること (空でない)
    func test_userMessage_allCodesHaveNonEmptyMessage() {
        for code in StateCode.allCases {
            XCTAssertFalse(code.userMessage.isEmpty,
                           "\(code.rawValue) should have a non-empty user message")
        }
    }

    /// 各コードのユーザー向け文言が仕様通りであること
    func test_userMessage_specificMessages_matchSpec() {
        XCTAssertEqual(StateCode.authNotGranted.userMessage,
                       "電力計測に必要な権限が未付与です")
        XCTAssertEqual(StateCode.helperNotRegistered.userMessage,
                       "計測ヘルパーを開始できません")
        XCTAssertEqual(StateCode.powerMetricsUnsupported.userMessage,
                       "この環境では電力値を取得できません")
        XCTAssertEqual(StateCode.initialDataPending.userMessage,
                       "最新データを取得中です")
        XCTAssertEqual(StateCode.powerDataFailure.userMessage,
                       "電力データの取得または解析に失敗しました")
        XCTAssertEqual(StateCode.wifiInterfaceUnknown.userMessage,
                       "Wi-Fi インターフェースを特定できません")
        XCTAssertEqual(StateCode.staleContinued.userMessage,
                       "データが古くなっています。表示値は参考値です")
        XCTAssertEqual(StateCode.databaseFailure.userMessage,
                       "保存領域にアクセスできません")
        XCTAssertEqual(StateCode.wifiDisconnected.userMessage,
                       "Wi-Fi が接続されていません")
    }

    // MARK: - Affected Scope

    /// 影響範囲が正しく設定されていること
    func test_affectedScope_correctForAllCodes() {
        XCTAssertEqual(StateCode.authNotGranted.affectedScope, .power)
        XCTAssertEqual(StateCode.helperNotRegistered.affectedScope, .powerAndWifi)
        XCTAssertEqual(StateCode.powerMetricsUnsupported.affectedScope, .power)
        XCTAssertEqual(StateCode.initialDataPending.affectedScope, .powerAndWifi)
        XCTAssertEqual(StateCode.powerDataFailure.affectedScope, .power)
        XCTAssertEqual(StateCode.wifiInterfaceUnknown.affectedScope, .wifi)
        XCTAssertEqual(StateCode.staleContinued.affectedScope, .powerOrWifi)
        XCTAssertEqual(StateCode.databaseFailure.affectedScope, .storage)
        XCTAssertEqual(StateCode.wifiDisconnected.affectedScope, .wifi)
    }

    // MARK: - Primary Action

    /// 全コードに主操作が設定されていること
    func test_primaryAction_allCodesHaveNonEmptyAction() {
        for code in StateCode.allCases {
            XCTAssertFalse(code.primaryAction.isEmpty,
                           "\(code.rawValue) should have a non-empty primary action")
        }
    }

    // MARK: - Codable

    /// rawValue からの初期化が正しく動作すること
    func test_codable_rawValueInit_allCodesResolvable() {
        for code in StateCode.allCases {
            let decoded = StateCode(rawValue: code.rawValue)
            XCTAssertEqual(decoded, code, "Should decode \(code.rawValue) correctly")
        }
    }

    /// 不正な rawValue からの初期化は nil になること
    func test_codable_invalidRawValue_returnsNil() {
        XCTAssertNil(StateCode(rawValue: "M-000"))
        XCTAssertNil(StateCode(rawValue: "M-010"))
        XCTAssertNil(StateCode(rawValue: ""))
        XCTAssertNil(StateCode(rawValue: "invalid"))
    }
}
