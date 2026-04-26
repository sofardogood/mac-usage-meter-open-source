import Foundation
import Combine
import SwiftUI
import ServiceManagement

/// 設定画面の ViewModel (G-004)
///
/// 設定値のバリデーション、保存、Collector への通知を担当する。
@MainActor
final class SettingsViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var launchAtLoginEnabled: Bool = true
    @Published var electricityUnitPriceYen: String = "31.0"
    @Published var networkTariffModel: TariffModel = .fixed
    @Published var monthlyFeeYen: String = "0"
    @Published var pricePerGbYen: String = "0"
    @Published var maxMonthlyFeeYen: String = "0"
    @Published var powerSamplingIntervalSec: Int = 60
    @Published var wifiSamplingIntervalSec: Int = 10
    @Published var retentionDays: Int = 90
    @Published var debugCaptureEnabled: Bool = false
    @Published var logLevel: String = "info"
    @Published var monthlyResetDay: Int = 1

    /// バリデーションエラー (フィールドキー -> エラーメッセージ)
    @Published var validationErrors: [String: String] = [:]

    /// 保存成功トースト表示
    @Published var showSaveToast: Bool = false

    /// 保存エラーメッセージ
    @Published var saveErrorMessage: String?

    // MARK: - Dependencies

    private let databaseManager: DatabaseManager
    private let collectorController: CollectorController

    // MARK: - Initialization

    init(databaseManager: DatabaseManager, collectorController: CollectorController) {
        self.databaseManager = databaseManager
        self.collectorController = collectorController
    }

    // MARK: - Load

    /// DB から設定を読み込む
    func loadSettings() {
        guard let settings = try? databaseManager.fetchAllSettings() else { return }
        let settingsMap = Dictionary(uniqueKeysWithValues: settings.map { ($0.key, $0) })

        if let val = settingsMap[AppSetting.Key.launchAtLoginEnabled.rawValue]?.valueBool {
            launchAtLoginEnabled = val != 0
        }
        if let val = settingsMap[AppSetting.Key.electricityUnitPriceYen.rawValue]?.valueNumber {
            electricityUnitPriceYen = String(format: "%.2f", val)
        }
        if let val = settingsMap[AppSetting.Key.networkTariffModel.rawValue]?.valueText,
           let model = TariffModel(rawValue: val) {
            networkTariffModel = model
        }
        if let val = settingsMap[AppSetting.Key.monthlyFeeYen.rawValue]?.valueNumber {
            monthlyFeeYen = String(format: "%.2f", val)
        }
        if let val = settingsMap[AppSetting.Key.pricePerGbYen.rawValue]?.valueNumber {
            pricePerGbYen = String(format: "%.2f", val)
        }
        if let val = settingsMap[AppSetting.Key.maxMonthlyFeeYen.rawValue]?.valueNumber {
            maxMonthlyFeeYen = String(format: "%.2f", val)
        }
        if let val = settingsMap[AppSetting.Key.powerSamplingIntervalSec.rawValue]?.valueNumber {
            powerSamplingIntervalSec = Int(val)
        }
        if let val = settingsMap[AppSetting.Key.wifiSamplingIntervalSec.rawValue]?.valueNumber {
            wifiSamplingIntervalSec = Int(val)
        }
        if let val = settingsMap[AppSetting.Key.retentionDays.rawValue]?.valueNumber {
            retentionDays = Int(val)
        }
        if let val = settingsMap[AppSetting.Key.debugCaptureEnabled.rawValue]?.valueBool {
            debugCaptureEnabled = val != 0
        }
        if let val = settingsMap[AppSetting.Key.logLevel.rawValue]?.valueText {
            logLevel = val
        }
        if let val = settingsMap[AppSetting.Key.monthlyResetDay.rawValue]?.valueNumber {
            monthlyResetDay = Int(val)
        }
    }

    // MARK: - Validation (5.4.1節)

    /// 依存バリデーションを含む全項目のバリデーション
    /// - Returns: バリデーションが成功した場合 true
    func validate() -> Bool {
        validationErrors.removeAll()

        // 電力単価
        if let price = Double(electricityUnitPriceYen) {
            if price < 0.0 || price > 999.99 {
                validationErrors["electricityUnitPriceYen"] = "0.00〜999.99 の範囲で入力してください"
            }
        } else {
            validationErrors["electricityUnitPriceYen"] = "有効な数値を入力してください"
        }

        // network_tariff_model 依存バリデーション
        switch networkTariffModel {
        case .fixed:
            if let fee = Double(monthlyFeeYen) {
                if fee < 0.0 || fee > 999_999.99 {
                    validationErrors["monthlyFeeYen"] = "0.00〜999999.99 の範囲で入力してください"
                }
            } else {
                validationErrors["monthlyFeeYen"] = "固定月額を入力してください"
            }
        case .metered:
            if let price = Double(pricePerGbYen) {
                if price < 0.0 || price > 9_999.99 {
                    validationErrors["pricePerGbYen"] = "0.00〜9999.99 の範囲で入力してください"
                }
            } else {
                validationErrors["pricePerGbYen"] = "GB 単価を入力してください"
            }
        case .cappedMetered:
            if let fee = Double(monthlyFeeYen) {
                if fee < 0.0 || fee > 999_999.99 {
                    validationErrors["monthlyFeeYen"] = "0.00〜999999.99 の範囲で入力してください"
                }
            } else {
                validationErrors["monthlyFeeYen"] = "固定月額を入力してください"
            }
            if let price = Double(pricePerGbYen) {
                if price < 0.0 || price > 9_999.99 {
                    validationErrors["pricePerGbYen"] = "0.00〜9999.99 の範囲で入力してください"
                }
            } else {
                validationErrors["pricePerGbYen"] = "GB 単価を入力してください"
            }
            if let max = Double(maxMonthlyFeeYen) {
                if max < 0.0 || max > 999_999.99 {
                    validationErrors["maxMonthlyFeeYen"] = "0.00〜999999.99 の範囲で入力してください"
                }
            } else {
                validationErrors["maxMonthlyFeeYen"] = "月額上限を入力してください"
            }
        }

        // 採取間隔
        if powerSamplingIntervalSec < 1 || powerSamplingIntervalSec > 300 {
            validationErrors["powerSamplingIntervalSec"] = "30〜300 秒の範囲で入力してください"
        }
        if wifiSamplingIntervalSec < 1 || wifiSamplingIntervalSec > 60 {
            validationErrors["wifiSamplingIntervalSec"] = "5〜60 秒の範囲で入力してください"
        }

        // 保持期間
        if retentionDays < 7 || retentionDays > 365 {
            validationErrors["retentionDays"] = "7〜365 日の範囲で入力してください"
        }

        // 月次リセット日
        if monthlyResetDay < 1 || monthlyResetDay > 28 {
            validationErrors["monthlyResetDay"] = "1〜28 の範囲で入力してください"
        }

        // ログレベル
        let validLogLevels = ["debug", "info", "warn", "error"]
        if !validLogLevels.contains(logLevel) {
            validationErrors["logLevel"] = "debug / info / warn / error のいずれかを選択してください"
        }

        return validationErrors.isEmpty
    }

    // MARK: - Save

    /// 設定を保存する
    func save() {
        guard validate() else { return }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        do {
            // ログイン時起動
            try databaseManager.upsertSetting(AppSetting(
                key: AppSetting.Key.launchAtLoginEnabled.rawValue,
                valueText: nil, valueNumber: nil,
                valueBool: launchAtLoginEnabled ? 1 : 0,
                updatedAtMs: nowMs
            ))

            // SMAppService でログイン時起動を設定
            if launchAtLoginEnabled {
                SetupViewModel.registerLoginItem()
            } else {
                SetupViewModel.unregisterLoginItem()
            }

            // 電力単価
            try databaseManager.upsertSetting(AppSetting(
                key: AppSetting.Key.electricityUnitPriceYen.rawValue,
                valueText: nil, valueNumber: Double(electricityUnitPriceYen),
                valueBool: nil, updatedAtMs: nowMs
            ))

            // 通信契約モデル
            try databaseManager.upsertSetting(AppSetting(
                key: AppSetting.Key.networkTariffModel.rawValue,
                valueText: networkTariffModel.rawValue, valueNumber: nil,
                valueBool: nil, updatedAtMs: nowMs
            ))

            // 依存フィールド: 無効なフィールドは NULL で保存
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

            // 電力採取間隔
            try databaseManager.upsertSetting(AppSetting(
                key: AppSetting.Key.powerSamplingIntervalSec.rawValue,
                valueText: nil, valueNumber: Double(powerSamplingIntervalSec),
                valueBool: nil, updatedAtMs: nowMs
            ))

            // Wi-Fi 採取間隔
            try databaseManager.upsertSetting(AppSetting(
                key: AppSetting.Key.wifiSamplingIntervalSec.rawValue,
                valueText: nil, valueNumber: Double(wifiSamplingIntervalSec),
                valueBool: nil, updatedAtMs: nowMs
            ))

            // 保持期間
            try databaseManager.upsertSetting(AppSetting(
                key: AppSetting.Key.retentionDays.rawValue,
                valueText: nil, valueNumber: Double(retentionDays),
                valueBool: nil, updatedAtMs: nowMs
            ))

            // デバッグ採取保存
            try databaseManager.upsertSetting(AppSetting(
                key: AppSetting.Key.debugCaptureEnabled.rawValue,
                valueText: nil, valueNumber: nil,
                valueBool: debugCaptureEnabled ? 1 : 0,
                updatedAtMs: nowMs
            ))

            // ログレベル
            try databaseManager.upsertSetting(AppSetting(
                key: AppSetting.Key.logLevel.rawValue,
                valueText: logLevel, valueNumber: nil,
                valueBool: nil, updatedAtMs: nowMs
            ))

            // 月次リセット日
            try databaseManager.upsertSetting(AppSetting(
                key: AppSetting.Key.monthlyResetDay.rawValue,
                valueText: nil, valueNumber: Double(monthlyResetDay),
                valueBool: nil, updatedAtMs: nowMs
            ))

            // Collector に設定再読込を通知
            Task {
                await collectorController.reloadSettings()
            }

            showSaveToast = true
            saveErrorMessage = nil

            // 3秒後にトーストを消す
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                showSaveToast = false
            }

        } catch {
            saveErrorMessage = "設定の保存に失敗しました: \(error.localizedDescription)"
            // 5秒後にエラーメッセージを消す
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                saveErrorMessage = nil
            }
        }
    }

    // MARK: - Tariff Model Helpers

    /// 固定月額フィールドが有効かどうか
    var isMonthlyFeeEnabled: Bool {
        networkTariffModel == .fixed || networkTariffModel == .cappedMetered
    }

    /// GB 単価フィールドが有効かどうか
    var isPricePerGbEnabled: Bool {
        networkTariffModel == .metered || networkTariffModel == .cappedMetered
    }

    /// 月額上限フィールドが有効かどうか
    var isMaxMonthlyFeeEnabled: Bool {
        networkTariffModel == .cappedMetered
    }
}
