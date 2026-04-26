import XCTest
@testable import MacUsageMeter

/// ErrorCode の単体テスト (第13章)
///
/// 観点: rawValue の完全性、stateCode マッピング、isRetryable、userMessage
final class ErrorCodeTests: XCTestCase {

    // MARK: - Completeness

    /// 全20コードが定義されていること
    func test_allCases_twentyCodesExist() {
        XCTAssertEqual(ErrorCode.allCases.count, 20)
    }

    /// rawValue が期待通りであること
    func test_rawValues_correctMapping() {
        XCTAssertEqual(ErrorCode.authPrivilegeFailure.rawValue, "AUTH-001")
        XCTAssertEqual(ErrorCode.authStateCheckFailure.rawValue, "AUTH-002")
        XCTAssertEqual(ErrorCode.helperNotAvailable.rawValue, "HELP-001")
        XCTAssertEqual(ErrorCode.powerMetricsExecFailure.rawValue, "PWR-001")
        XCTAssertEqual(ErrorCode.powerMetricsUnsupported.rawValue, "PWR-002")
        XCTAssertEqual(ErrorCode.powerParserFailure.rawValue, "PWR-003")
        XCTAssertEqual(ErrorCode.powerTimeout.rawValue, "PWR-004")
        XCTAssertEqual(ErrorCode.netInterfaceUnknown.rawValue, "NET-001")
        XCTAssertEqual(ErrorCode.netCounterReset.rawValue, "NET-002")
        XCTAssertEqual(ErrorCode.netSnapshotFailure.rawValue, "NET-003")
        XCTAssertEqual(ErrorCode.dbOpenFailure.rawValue, "DB-001")
        XCTAssertEqual(ErrorCode.dbWriteFailure.rawValue, "DB-002")
        XCTAssertEqual(ErrorCode.dbMigrationFailure.rawValue, "DB-003")
        XCTAssertEqual(ErrorCode.ipcPingFailure.rawValue, "IPC-001")
        XCTAssertEqual(ErrorCode.ipcServiceStatusFailure.rawValue, "IPC-002")
        XCTAssertEqual(ErrorCode.ipcCapabilitiesFailure.rawValue, "IPC-003")
        XCTAssertEqual(ErrorCode.ipcPowerSampleFailure.rawValue, "IPC-004")
        XCTAssertEqual(ErrorCode.ipcWifiSnapshotFailure.rawValue, "IPC-005")
        XCTAssertEqual(ErrorCode.ipcHealthReportFailure.rawValue, "IPC-006")
        XCTAssertEqual(ErrorCode.debugRotateFailure.rawValue, "DBG-001")
    }

    // MARK: - State Code Mapping

    /// AUTH 系 → M-001 (authNotGranted)
    func test_stateCode_authCodes_mapToAuthNotGranted() {
        XCTAssertEqual(ErrorCode.authPrivilegeFailure.stateCode, .authNotGranted)
        XCTAssertEqual(ErrorCode.authStateCheckFailure.stateCode, .authNotGranted)
    }

    /// HELP/IPC-001〜003 系 → M-002 (helperNotRegistered)
    func test_stateCode_helperCodes_mapToHelperNotRegistered() {
        XCTAssertEqual(ErrorCode.helperNotAvailable.stateCode, .helperNotRegistered)
        XCTAssertEqual(ErrorCode.ipcPingFailure.stateCode, .helperNotRegistered)
        XCTAssertEqual(ErrorCode.ipcServiceStatusFailure.stateCode, .helperNotRegistered)
        XCTAssertEqual(ErrorCode.ipcCapabilitiesFailure.stateCode, .helperNotRegistered)
    }

    /// PWR-002 → M-003 (powerMetricsUnsupported)
    func test_stateCode_pwrUnsupported_mapToPowerMetricsUnsupported() {
        XCTAssertEqual(ErrorCode.powerMetricsUnsupported.stateCode, .powerMetricsUnsupported)
    }

    /// PWR-001/003/004, IPC-004 → M-005 (powerDataFailure)
    func test_stateCode_pwrFailureCodes_mapToPowerDataFailure() {
        XCTAssertEqual(ErrorCode.powerMetricsExecFailure.stateCode, .powerDataFailure)
        XCTAssertEqual(ErrorCode.powerParserFailure.stateCode, .powerDataFailure)
        XCTAssertEqual(ErrorCode.powerTimeout.stateCode, .powerDataFailure)
        XCTAssertEqual(ErrorCode.ipcPowerSampleFailure.stateCode, .powerDataFailure)
    }

    /// NET-001/003, IPC-005 → M-006 (wifiInterfaceUnknown)
    func test_stateCode_netCodes_mapToWifiInterfaceUnknown() {
        XCTAssertEqual(ErrorCode.netInterfaceUnknown.stateCode, .wifiInterfaceUnknown)
        XCTAssertEqual(ErrorCode.netSnapshotFailure.stateCode, .wifiInterfaceUnknown)
        XCTAssertEqual(ErrorCode.ipcWifiSnapshotFailure.stateCode, .wifiInterfaceUnknown)
    }

    /// DB 系 → M-008 (databaseFailure)
    func test_stateCode_dbCodes_mapToDatabaseFailure() {
        XCTAssertEqual(ErrorCode.dbOpenFailure.stateCode, .databaseFailure)
        XCTAssertEqual(ErrorCode.dbWriteFailure.stateCode, .databaseFailure)
        XCTAssertEqual(ErrorCode.dbMigrationFailure.stateCode, .databaseFailure)
    }

    /// stateCode なしのコード (NET-002, IPC-006, DBG-001)
    func test_stateCode_noStateCode_returnsNil() {
        XCTAssertNil(ErrorCode.netCounterReset.stateCode)
        XCTAssertNil(ErrorCode.ipcHealthReportFailure.stateCode)
        XCTAssertNil(ErrorCode.debugRotateFailure.stateCode)
    }

    // MARK: - Retryable

    /// リトライ不可: AUTH-001, PWR-002, IPC-006, DBG-001
    func test_isRetryable_nonRetryableCodes() {
        XCTAssertFalse(ErrorCode.authPrivilegeFailure.isRetryable)
        XCTAssertFalse(ErrorCode.powerMetricsUnsupported.isRetryable)
        XCTAssertFalse(ErrorCode.ipcHealthReportFailure.isRetryable)
        XCTAssertFalse(ErrorCode.debugRotateFailure.isRetryable)
    }

    /// リトライ可能なコードの数
    func test_isRetryable_retryableCodesCount() {
        let retryable = ErrorCode.allCases.filter(\.isRetryable)
        XCTAssertEqual(retryable.count, 16)
    }

    /// AUTH-002 はリトライ可能
    func test_isRetryable_authStateCheck_retryable() {
        XCTAssertTrue(ErrorCode.authStateCheckFailure.isRetryable)
    }

    /// HELP-001 はリトライ可能
    func test_isRetryable_helperNotAvailable_retryable() {
        XCTAssertTrue(ErrorCode.helperNotAvailable.isRetryable)
    }

    /// DB 系は全てリトライ可能
    func test_isRetryable_dbCodes_allRetryable() {
        XCTAssertTrue(ErrorCode.dbOpenFailure.isRetryable)
        XCTAssertTrue(ErrorCode.dbWriteFailure.isRetryable)
        XCTAssertTrue(ErrorCode.dbMigrationFailure.isRetryable)
    }

    // MARK: - User Message

    /// 全コードにユーザー向け文言が設定されていること (空でない)
    func test_userMessage_allCodesHaveNonEmptyMessage() {
        for code in ErrorCode.allCases {
            XCTAssertFalse(code.userMessage.isEmpty,
                           "\(code.rawValue) should have a non-empty user message")
        }
    }

    /// 特定のコードの文言が仕様通りであること
    func test_userMessage_specificMessages() {
        XCTAssertEqual(ErrorCode.authPrivilegeFailure.userMessage, "電力計測の権限が未付与です")
        XCTAssertEqual(ErrorCode.helperNotAvailable.userMessage, "計測ヘルパーを開始できません")
        XCTAssertEqual(ErrorCode.dbOpenFailure.userMessage, "保存領域にアクセスできません")
        XCTAssertEqual(ErrorCode.netCounterReset.userMessage, "通信量を一時的に集計できません")
    }

    // MARK: - Codable

    /// rawValue からの初期化が正しく動作すること
    func test_codable_allCodesResolvable() {
        for code in ErrorCode.allCases {
            let decoded = ErrorCode(rawValue: code.rawValue)
            XCTAssertEqual(decoded, code, "Should decode \(code.rawValue)")
        }
    }

    /// 不正な rawValue は nil
    func test_codable_invalidRawValue_returnsNil() {
        XCTAssertNil(ErrorCode(rawValue: "INVALID"))
        XCTAssertNil(ErrorCode(rawValue: ""))
        XCTAssertNil(ErrorCode(rawValue: "AUTH-999"))
    }
}
