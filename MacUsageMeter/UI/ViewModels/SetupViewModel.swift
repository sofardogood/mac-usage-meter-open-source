import Foundation
import Combine
import SwiftUI
import ServiceManagement
import os.log

/// 初回セットアップの ViewModel (G-005)
///
/// 5ステップウィザードの状態管理、Helper 登録、試験採取を担当する。
@MainActor
final class SetupViewModel: ObservableObject {

    // MARK: - Published Properties

    /// 現在のステップ (1〜5)
    @Published var currentStep: Int = 1

    /// Helper 登録状態
    @Published var helperRegistrationState: HelperRegistrationState = .notStarted

    /// Collector 状態
    @Published var collectorState: CollectorState = .starting

    /// 料金設定
    @Published var electricityUnitPriceYen: String = "31.0"
    @Published var networkTariffModel: TariffModel = .fixed
    @Published var monthlyFeeYen: String = "0"
    @Published var pricePerGbYen: String = "0"
    @Published var maxMonthlyFeeYen: String = "0"

    /// 試験採取の結果
    @Published var testPowerResult: TestResult = .notStarted
    @Published var testWifiResult: TestResult = .notStarted
    @Published var testPowerMessage: String = ""
    @Published var testWifiMessage: String = ""

    /// 料金設定のバリデーションエラー
    @Published var tariffValidationErrors: [String: String] = [:]

    /// ログイン時起動
    @Published var launchAtLoginEnabled: Bool = true

    // MARK: - Enums

    enum HelperRegistrationState {
        case notStarted
        case registering
        case registered
        case failed(String)
    }

    enum TestResult {
        case notStarted
        case running
        case success
        case failed(String)

        var isSuccess: Bool {
            if case .success = self { return true }
            return false
        }
    }

    // MARK: - Dependencies

    private let collectorController: CollectorController
    private let databaseManager: DatabaseManager

    static let totalSteps = 5

    // MARK: - Initialization

    init(collectorController: CollectorController, databaseManager: DatabaseManager) {
        self.collectorController = collectorController
        self.databaseManager = databaseManager
    }

    // MARK: - Navigation

    /// 次のステップに進む
    func goToNextStep() {
        // ステップ 3 から離れる際にバリデーションエラーを表示する
        if currentStep == 3 {
            _ = validateTariffSettings()
        }
        if currentStep < Self.totalSteps {
            currentStep += 1
        }
    }

    /// 前のステップに戻る
    func goToPreviousStep() {
        if currentStep > 1 {
            currentStep -= 1
        }
    }

    /// 現在のステップが完了条件を満たしているか
    var canProceed: Bool {
        switch currentStep {
        case 1:
            return true // 概要説明は常に「次へ」可能
        case 2:
            switch helperRegistrationState {
            case .registered: return true
            case .failed: return true // 開発時: Helper 登録失敗でもスキップ可能
            default: return false
            }
        case 3:
            return isTariffValid()
        case 4:
            // テスト未実行でもスキップ可能（Helper なしの開発モード対応）
            switch testWifiResult {
            case .success:
                switch testPowerResult {
                case .success, .failed: return true
                default: return false
                }
            case .failed:
                return true // 失敗でも先に進める
            case .notStarted:
                return true // 未実行でもスキップ可能
            default:
                return false
            }
        case 5:
            return true
        default:
            return false
        }
    }

    // MARK: - Step 2: Helper 登録

    /// Helper を登録する
    ///
    /// SMAppService.daemon() による登録を試みる。署名なし開発ビルドでは
    /// 必ず失敗するため、ローカル開発モードの案内を含むエラーメッセージを表示する。
    func registerHelper() {
        helperRegistrationState = .registering
        Task {
            // dev モード: launchd 経由で起動済みの Helper をセンチネルで検出
            if FileManager.default.fileExists(atPath: "/tmp/com.macusagemeter.helper.local.ready") {
                await collectorController.start()
                let state = await collectorController.state
                collectorState = state
                if state == .normal || state == .limitedReady {
                    helperRegistrationState = .registered
                } else {
                    helperRegistrationState = .failed("ローカル Helper への接続に失敗しました（状態: \(state.rawValue)）")
                }
                return
            }

            do {
                try SMAppService.daemon(plistName: "\(Bundle.main.bundleIdentifier ?? "com.macusagemeter").helper.plist").register()
                await collectorController.start()
                let state = await collectorController.state
                collectorState = state
                if state == .normal || state == .limitedReady {
                    helperRegistrationState = .registered
                } else {
                    helperRegistrationState = .failed("Collector の初期化に失敗しました（状態: \(state.rawValue)）")
                }
            } catch {
                #if DEBUG
                let devHint = """
                    署名なし開発ビルドでは Helper の自動登録はできません。\
                    ローカル開発モードを使用してください:

                    1. ターミナルで Scripts/dev-setup.sh を実行
                    2. Helper が --local モードで起動します（sudo 必要）
                    3. アプリは自動的にローカル Helper に接続します

                    電力計測が不要な場合は「スキップして続行」で Wi-Fi のみモードで動作します。
                    """
                helperRegistrationState = .failed(devHint)
                #else
                helperRegistrationState = .failed("Helper の登録に失敗しました: \(error.localizedDescription)")
                #endif
            }
        }
    }

    // MARK: - Step 3: 料金設定バリデーション

    /// 副作用なしのバリデーション判定（canProceed 用）
    private func isTariffValid() -> Bool {
        guard Double(electricityUnitPriceYen) != nil else { return false }
        if let price = Double(electricityUnitPriceYen), (price < 0.0 || price > 999.99) { return false }
        switch networkTariffModel {
        case .fixed:
            if Double(monthlyFeeYen) == nil { return false }
        case .metered:
            if Double(pricePerGbYen) == nil { return false }
        case .cappedMetered:
            if Double(monthlyFeeYen) == nil { return false }
            if Double(pricePerGbYen) == nil { return false }
            if Double(maxMonthlyFeeYen) == nil { return false }
        }
        return true
    }

    /// 料金設定のバリデーション（エラーメッセージ付き、保存時に呼ぶ）
    func validateTariffSettings() -> Bool {
        tariffValidationErrors.removeAll()

        if let price = Double(electricityUnitPriceYen) {
            if price < 0.0 || price > 999.99 {
                tariffValidationErrors["electricityUnitPriceYen"] = "0.00〜999.99 の範囲で入力してください"
            }
        } else {
            tariffValidationErrors["electricityUnitPriceYen"] = "有効な数値を入力してください"
        }

        switch networkTariffModel {
        case .fixed:
            if Double(monthlyFeeYen) == nil {
                tariffValidationErrors["monthlyFeeYen"] = "固定月額を入力してください"
            }
        case .metered:
            if Double(pricePerGbYen) == nil {
                tariffValidationErrors["pricePerGbYen"] = "GB 単価を入力してください"
            }
        case .cappedMetered:
            if Double(monthlyFeeYen) == nil {
                tariffValidationErrors["monthlyFeeYen"] = "固定月額を入力してください"
            }
            if Double(pricePerGbYen) == nil {
                tariffValidationErrors["pricePerGbYen"] = "GB 単価を入力してください"
            }
            if Double(maxMonthlyFeeYen) == nil {
                tariffValidationErrors["maxMonthlyFeeYen"] = "月額上限を入力してください"
            }
        }

        return tariffValidationErrors.isEmpty
    }

    // MARK: - Step 4: 試験採取

    /// 試験採取を実行する
    func runTestSampling() {
        testPowerResult = .running
        testWifiResult = .running
        testPowerMessage = "電力データを取得中..."
        testWifiMessage = "Wi-Fi データを取得中..."

        Task {
            // 電力サンプル取得
            await collectorController.collectPowerSample()
            let powerSample = await collectorController.getLatestPowerSample()
            if let sample = powerSample, sample.status == .success || sample.status == .partial {
                testPowerResult = .success
                if let watts = sample.avgWatts {
                    testPowerMessage = "電力データの取得に成功しました（\(String(format: "%.1f", watts)) W）"
                } else {
                    testPowerMessage = "電力データの取得に成功しました"
                }
            } else {
                let reason = powerSample?.errorCode ?? "不明なエラー"
                testPowerResult = .failed(reason)
                testPowerMessage = "電力データの取得に失敗しました（\(reason)）\nこの環境では電力の計測ができない可能性があります。"
            }

            // Wi-Fi スナップショット取得
            await collectorController.collectWifiSnapshot()
            let wifiSample = await collectorController.getLatestWifiSample()
            if let sample = wifiSample, sample.status == .success {
                testWifiResult = .success
                testWifiMessage = "Wi-Fi データの取得に成功しました（インターフェース: \(sample.interfaceName)）"
            } else {
                let reason = wifiSample?.errorCode ?? "不明なエラー"
                testWifiResult = .failed(reason)
                testWifiMessage = "Wi-Fi データの取得に失敗しました（\(reason)）"
            }
        }
    }

    // MARK: - Step 5: 完了

    /// セットアップを完了する
    func completeSetup() {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        do {
            // setup_completed_at を保存
            try databaseManager.upsertSetting(AppSetting(
                key: AppSetting.Key.setupCompletedAt.rawValue,
                valueText: nil, valueNumber: Double(nowMs),
                valueBool: nil, updatedAtMs: nowMs
            ))

            // 料金設定を保存
            try databaseManager.upsertSetting(AppSetting(
                key: AppSetting.Key.electricityUnitPriceYen.rawValue,
                valueText: nil, valueNumber: Double(electricityUnitPriceYen),
                valueBool: nil, updatedAtMs: nowMs
            ))
            try databaseManager.upsertSetting(AppSetting(
                key: AppSetting.Key.networkTariffModel.rawValue,
                valueText: networkTariffModel.rawValue, valueNumber: nil,
                valueBool: nil, updatedAtMs: nowMs
            ))

            let monthlyFeeValue: Double? = (networkTariffModel == .fixed || networkTariffModel == .cappedMetered)
                ? Double(monthlyFeeYen) : nil
            try databaseManager.upsertSetting(AppSetting(
                key: AppSetting.Key.monthlyFeeYen.rawValue,
                valueText: nil, valueNumber: monthlyFeeValue,
                valueBool: nil, updatedAtMs: nowMs
            ))

            let pricePerGbValue: Double? = (networkTariffModel == .metered || networkTariffModel == .cappedMetered)
                ? Double(pricePerGbYen) : nil
            try databaseManager.upsertSetting(AppSetting(
                key: AppSetting.Key.pricePerGbYen.rawValue,
                valueText: nil, valueNumber: pricePerGbValue,
                valueBool: nil, updatedAtMs: nowMs
            ))

            let maxMonthlyFeeValue: Double? = (networkTariffModel == .cappedMetered)
                ? Double(maxMonthlyFeeYen) : nil
            try databaseManager.upsertSetting(AppSetting(
                key: AppSetting.Key.maxMonthlyFeeYen.rawValue,
                valueText: nil, valueNumber: maxMonthlyFeeValue,
                valueBool: nil, updatedAtMs: nowMs
            ))

            // ログイン時起動
            try databaseManager.upsertSetting(AppSetting(
                key: AppSetting.Key.launchAtLoginEnabled.rawValue,
                valueText: nil, valueNumber: nil,
                valueBool: launchAtLoginEnabled ? 1 : 0,
                updatedAtMs: nowMs
            ))
            if launchAtLoginEnabled {
                Self.registerLoginItem()
            }

            // Collector に設定再読込を通知
            Task {
                await collectorController.reloadSettings()
            }
        } catch {
            // DB 書込み失敗は unified logging で記録 (バックエンドが実装)
        }
    }

    // MARK: - Login Item Helper

    /// ログイン項目の登録を試みる。SPM デバッグビルドでは bundle identifier が
    /// launchd に登録されていないため SMAppService が失敗する。その場合はログを出して無視する。
    static func registerLoginItem() {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MacUsageMeter", category: "LoginItem")

        // SPM デバッグビルド判定: bundle identifier が未設定または "MacUsageMeter" を含む場合はスキップ
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        if bundleID.isEmpty || bundleID == "MacUsageMeter" {
            logger.debug("SPM debug build detected (bundleIdentifier=\(bundleID, privacy: .public)). Skipping login item registration.")
            return
        }

        do {
            try SMAppService.mainApp.register()
            logger.info("Login item registered successfully.")
        } catch {
            logger.warning("Failed to register login item: \(error.localizedDescription, privacy: .public). This is expected in debug/unsigned builds.")
        }
    }

    /// ログイン項目の登録解除を試みる。
    static func unregisterLoginItem() {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MacUsageMeter", category: "LoginItem")

        let bundleID = Bundle.main.bundleIdentifier ?? ""
        if bundleID.isEmpty || bundleID == "MacUsageMeter" {
            logger.debug("SPM debug build detected (bundleIdentifier=\(bundleID, privacy: .public)). Skipping login item unregistration.")
            return
        }

        do {
            try SMAppService.mainApp.unregister()
            logger.info("Login item unregistered successfully.")
        } catch {
            logger.warning("Failed to unregister login item: \(error.localizedDescription, privacy: .public). This is expected in debug/unsigned builds.")
        }
    }
}
