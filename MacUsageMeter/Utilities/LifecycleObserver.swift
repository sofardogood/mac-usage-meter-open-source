import Foundation
import AppKit

/// ライフサイクルオブザーバ (第14章)
///
/// sleep/wake、蓋閉じ、時刻変更、DST、ディスクフルを監視し、
/// Collector Controller に適切なイベントを通知する。
final class LifecycleObserver {

    /// Collector Controller への弱参照用クロージャ
    var onSleepWillStart: (() -> Void)?
    var onWakeDidComplete: (() -> Void)?
    var onTimeZoneDidChange: (() -> Void)?
    var onSystemClockDidChange: (() -> Void)?

    /// ディスク空き容量不足の閾値 (100MB)
    private static let diskSpaceThresholdBytes: UInt64 = 100 * 1024 * 1024

    /// 監視中かどうか
    private var isObserving = false

    // MARK: - Initialization

    init() {}

    deinit {
        stopObserving()
    }

    // MARK: - Start / Stop

    /// 監視を開始する
    ///
    /// 以下の通知を監視:
    /// - NSWorkspace.willSleepNotification (sleep 突入)
    /// - NSWorkspace.didWakeNotification (wake 復帰)
    /// - NSNotification.Name.NSSystemTimeZoneDidChange (タイムゾーン変更 / DST)
    /// - NSNotification.Name.NSSystemClockDidChange (時計の手動変更)
    func startObserving() {
        guard !isObserving else { return }
        isObserving = true

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(
            self,
            selector: #selector(handleWillSleep(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        workspace.addObserver(
            self,
            selector: #selector(handleDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        let nc = NotificationCenter.default
        nc.addObserver(
            self,
            selector: #selector(handleTimeZoneDidChange(_:)),
            name: .NSSystemTimeZoneDidChange,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(handleSystemClockDidChange(_:)),
            name: .NSSystemClockDidChange,
            object: nil
        )
    }

    /// 監視を停止する
    func stopObserving() {
        guard isObserving else { return }
        isObserving = false

        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Disk Space

    /// ディスク空き容量を確認する
    ///
    /// 空き容量 < 100MB の場合は warn レベルで通知。
    ///
    /// - Returns: 空き容量 (バイト)
    func checkDiskSpace() -> UInt64 {
        let homeDir = NSHomeDirectory()
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: homeDir)
            if let freeSize = attrs[.systemFreeSize] as? UInt64 {
                return freeSize
            }
        } catch {
            // 取得失敗時は 0 を返す (警告を出す側で判定)
        }
        return 0
    }

    /// ディスク空き容量が不足しているか
    ///
    /// 閾値: 100MB
    ///
    /// - Returns: 不足している場合は true
    func isDiskSpaceLow() -> Bool {
        return checkDiskSpace() < Self.diskSpaceThresholdBytes
    }

    // MARK: - Private Handlers

    /// sleep 突入ハンドラ
    ///
    /// タイマーを停止。最後のサンプル時刻を記録。
    @objc private func handleWillSleep(_ notification: Notification) {
        onSleepWillStart?()
    }

    /// wake 復帰ハンドラ
    ///
    /// 5秒の安定待ちの後、タイマーを再開。
    /// Wi-Fi カウンタは差分計算をリセット (counter_reset_flag=1)。
    /// 日付をまたいだ場合は補完ロールアップを実行。
    @objc private func handleDidWake(_ notification: Notification) {
        // 5秒の安定待ち後に通知
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.onWakeDidComplete?()
        }
    }

    /// タイムゾーン変更ハンドラ
    ///
    /// 日次集計の日付境界を新 TZ で再計算。当日のロールアップを再実行。
    @objc private func handleTimeZoneDidChange(_ notification: Notification) {
        onTimeZoneDidChange?()
    }

    /// システムクロック変更ハンドラ
    ///
    /// captured_at_ms は UTC なので影響なし。ローカル日付の再計算のみ。
    @objc private func handleSystemClockDidChange(_ notification: Notification) {
        onSystemClockDidChange?()
    }
}
