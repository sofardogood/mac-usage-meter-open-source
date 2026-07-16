import SwiftUI
import AppKit
import Combine

extension Notification.Name {
    static let macUsageMeterStatusItemNeedsRefresh = Notification.Name("macUsageMeterStatusItemNeedsRefresh")
}

/// Mac Usage Meter - メニューバー常駐アプリのエントリポイント
///
/// 純粋な NSApplication + AppDelegate ベースで起動する。
/// SwiftUI App プロトコルは SPM ビルドで不安定なため使用しない。
@main
enum MacUsageMeterApp {
    static func main() {
        // シングルインスタンスガード: 既に同じアプリが起動中なら即終了
        let runningInstances = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.macusagemeter.app"
        )
        if runningInstances.count > 1 {
            // 自分より先に起動しているインスタンスがある
            exit(0)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Keep a normal application presence during startup. This provides a
        // visible fallback when macOS delays or suppresses a status-bar item.
        app.setActivationPolicy(.regular)
        // delegate を app.run() 終了まで保持する。
        // NSApplication.delegate は weak 参照のため、
        // withExtendedLifetime がないと ARC が早期解放する可能性がある。
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

/// AppDelegate - NSStatusItem のセットアップとアプリケーションライフサイクル管理
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// メニューバーに表示するステータスアイテム
    private var statusItem: NSStatusItem?

    /// ポップオーバーウインドウ
    private var popover: NSPopover?

    /// Collector Controller (Swift actor)
    private var collectorController: CollectorController?

    /// データベースマネージャ
    private var databaseManager: DatabaseManager?

    /// ライフサイクルオブザーバ
    private var lifecycleObserver: LifecycleObserver?

    /// メニューバー ViewModel
    private var menuBarViewModel: MenuBarViewModel?

    /// ポップオーバー ViewModel
    private var popoverViewModel: PopoverViewModel?

    /// 設定画面 ViewModel
    private var settingsViewModel: SettingsViewModel?

    /// セットアップ画面ウィンドウ
    private var setupWindow: NSWindow?

    /// 詳細画面ウィンドウ
    private var detailWindow: NSWindow?

    /// エラー状態画面ウィンドウ
    private var errorStateWindow: NSWindow?

    /// 設定画面ウィンドウ
    private var settingsWindow: NSWindow?

    private var cancellables = Set<AnyCancellable>()

    /// メニューバー項目が AppKit 側で外れた場合に復元する定期チェック
    private var statusItemVisibilityTimer: Timer?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. データベースマネージャを初期化
        do {
            databaseManager = try DatabaseManager()
        } catch {
            setupStatusItem()
            startStatusItemVisibilityWatchdog()
            statusItem?.button?.title = " Check"
            return
        }

        guard let db = databaseManager else { return }

        // 2. Collector Controller を初期化
        let xpcClient = XPCClient()
        let powerInterval = (try? db.fetchSetting(key: AppSetting.Key.powerSamplingIntervalSec.rawValue))?.valueNumber.flatMap { Int($0) } ??  3
        let wifiInterval = (try? db.fetchSetting(key: AppSetting.Key.wifiSamplingIntervalSec.rawValue))?.valueNumber.flatMap { Int($0) } ??  1

        let collector = CollectorController(
            xpcClient: xpcClient,
            databaseManager: db,
            powerInterval: powerInterval,
            wifiInterval: wifiInterval
        )
        collectorController = collector

        // 3. ViewModel を初期化
        menuBarViewModel = MenuBarViewModel(collectorController: collector, databaseManager: db)
        popoverViewModel = PopoverViewModel(collectorController: collector, databaseManager: db)
        settingsViewModel = SettingsViewModel(databaseManager: db, collectorController: collector)

        // 4. メニューバーをセットアップ
        setupStatusItem()
        startStatusItemVisibilityWatchdog()
        setupPopover()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(statusItemNeedsRefresh(_:)),
            name: .macUsageMeterStatusItemNeedsRefresh,
            object: nil
        )

        // 5. ライフサイクル監視
        lifecycleObserver = LifecycleObserver()
        setupLifecycleCallbacks()
        lifecycleObserver?.startObserving()

        // 6. メニューバー更新を開始 & StatusItem と連動
        menuBarViewModel?.startUpdating()
        observeMenuBarUpdates()

        // 7. 初回セットアップ確認
        checkSetupStatus()

        // 8. 設定読み込み
        settingsViewModel?.loadSettings()

        // 9. Collector を非同期で起動
        Task.detached(priority: .utility) {
            await collector.start()
        }

        // A visible window is a reliable fallback on systems that delay menu
        // bar item presentation during first launch.
        showDetailWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self, name: .macUsageMeterStatusItemNeedsRefresh, object: nil)
        menuBarViewModel?.stopUpdating()
        popoverViewModel?.stopUpdating()
        lifecycleObserver?.stopObserving()
        stopStatusItemVisibilityWatchdog()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        let item: NSStatusItem
        if let existingItem = statusItem {
            item = existingItem
            item.length = 32
        } else {
            // Reserve space immediately so an asynchronous first refresh cannot
            // leave the menu bar item with a zero-width, invisible button.
            item = NSStatusBar.system.statusItem(withLength: 32)
            statusItem = item
        }

        item.isVisible = true
        configureStatusItem(item)
    }

    private func configureStatusItem(_ item: NSStatusItem) {
        guard let button = item.button else { return }

        if let img = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Mac Usage Meter") {
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = true
            button.image = img
        }
        // Always leave a visible fallback while the first database refresh is
        // still in flight or an SF Symbol cannot be created.
        button.title = "⚡"
        button.action = #selector(statusItemClicked(_:))
        button.target = self
        button.toolTip = "Mac Usage Meter"
        button.setAccessibilityIdentifier("statusBarButton")
    }

    @objc private func statusItemNeedsRefresh(_ notification: Notification) {
        ensureStatusItemVisible()
    }

    private func ensureStatusItemVisible() {
        if statusItem?.button == nil {
            statusItem = nil
            setupStatusItem()
        }

        guard let item = statusItem else {
            setupStatusItem()
            return
        }

        item.isVisible = true
        menuBarViewModel?.updateStatusItem(item)
    }

    private func startStatusItemVisibilityWatchdog() {
        guard statusItemVisibilityTimer == nil else { return }

        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.ensureStatusItemVisible()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        statusItemVisibilityTimer = timer
    }

    private func stopStatusItemVisibilityWatchdog() {
        statusItemVisibilityTimer?.invalidate()
        statusItemVisibilityTimer = nil
    }

    private func setupPopover() {
        let pop = NSPopover()
        pop.contentSize = NSSize(width: 320, height: 380)
        pop.behavior = .transient
        pop.animates = true

        if let vm = popoverViewModel {
            let popoverView = PopoverView(viewModel: vm,
                onShowDetail: { [weak self] in self?.showDetailWindow() },
                onShowError: { [weak self] code in self?.showErrorStateWindow(stateCode: code) },
                onShowSettings: { [weak self] in self?.showSettingsWindow() },
                onQuit: { NSApplication.shared.terminate(nil) }
            )
            pop.contentViewController = NSHostingController(rootView: popoverView)
        }

        popover = pop
    }

    private func checkSetupStatus() {
        guard let db = databaseManager else { return }
        let completed = (try? db.fetchSetting(key: AppSetting.Key.setupCompletedAt.rawValue))?.valueNumber != nil
        if !completed {
            showSetupWindow()
        }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let button = statusItem?.button else { return }

        if let pop = popover, pop.isShown {
            pop.performClose(sender)
            popoverViewModel?.stopUpdating()
        } else {
            popoverViewModel?.startUpdating()
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    // MARK: - Menu Bar Update Binding

    /// MenuBarViewModel の displayState 変更を NSStatusItem に反映する
    private func observeMenuBarUpdates() {
        guard let vm = menuBarViewModel, let item = statusItem else { return }
        vm.$displayState
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.ensureStatusItemVisible()
            }
            .store(in: &cancellables)
        // 初回反映
        vm.updateStatusItem(item)
    }

    // MARK: - Lifecycle Callbacks

    /// LifecycleObserver のコールバックを Collector に接続する
    private func setupLifecycleCallbacks() {
        guard let collector = collectorController else { return }

        lifecycleObserver?.onSleepWillStart = {
            Task { await collector.stop() }
        }

        lifecycleObserver?.onWakeDidComplete = { [weak self] in
            Task {
                // Wi-Fi カウンタの差分計算基準をリセット (第14.1節: counter_reset_flag=1)
                await collector.resetWifiBaseline()
                await collector.start()
                await MainActor.run { self?.menuBarViewModel?.refresh() }
            }
        }

        lifecycleObserver?.onTimeZoneDidChange = {
            Task {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                let today = formatter.string(from: Date())
                await collector.performRollup(for: today)
            }
        }

        lifecycleObserver?.onSystemClockDidChange = { [weak self] in
            Task {
                await MainActor.run { self?.menuBarViewModel?.refresh() }
            }
        }
    }

    // MARK: - Windows

    func showSetupWindow() {
        guard let collector = collectorController, let db = databaseManager else { return }
        let vm = SetupViewModel(collectorController: collector, databaseManager: db)
        let view = SetupView(viewModel: vm) { [weak self] in
            self?.setupWindow?.close()
            self?.setupWindow = nil
        }

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Mac Usage Meter - Setup"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        setupWindow = window
    }

    func showDetailWindow() {
        guard let db = databaseManager else { return }

        // 既存ウィンドウがあれば再利用
        if let existing = detailWindow, existing.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            popover?.performClose(nil)
            return
        }

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 550),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        let viewModel = DetailViewModel(
            databaseManager: db,
            presentingWindowProvider: { [weak self] in self?.detailWindow }
        )
        let view = DetailView(viewModel: viewModel)
        window.title = "Mac Usage Meter - Details"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        detailWindow = window

        // ウィンドウを表示・アクティブにしてからポップオーバーを閉じる
        // (先にポップオーバーを閉じるとアクセサリアプリのアクティベーションが失われ、
        //  ウィンドウが前面に出ない問題が発生する)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        DispatchQueue.main.async { [weak self] in
            self?.popover?.performClose(nil)
        }
    }

    func showErrorStateWindow(stateCode: StateCode) {
        guard let collector = collectorController, let db = databaseManager else { return }
        let debugEnabled = (try? db.fetchSetting(key: AppSetting.Key.debugCaptureEnabled.rawValue))?.valueBool == 1

        let view = ErrorStateView(
            stateCode: stateCode,
            occurredAt: DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium),
            lastSuccessAt: nil, internalErrorCode: nil, isDebugEnabled: debugEnabled,
            onRetry: stateCode.isRetryable ? {
                Task { await collector.collectPowerSample(); await collector.collectWifiSnapshot() }
            } : nil,
            onRestartSetup: (stateCode == .authNotGranted || stateCode == .helperNotRegistered) ? { [weak self] in
                self?.errorStateWindow?.close(); self?.showSetupWindow()
            } : nil,
            onOpenSettings: { [weak self] in self?.showSettingsWindow() },
            onOpenLog: debugEnabled ? {} : nil,
            onDismiss: { [weak self] in self?.errorStateWindow?.close(); self?.errorStateWindow = nil }
        )

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 500),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Mac Usage Meter - Error Status"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        errorStateWindow = window
    }

    private func showSettingsWindow() {
        guard let vm = settingsViewModel else { return }

        // 既存ウィンドウがあれば再利用
        if let existing = settingsWindow, existing.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            popover?.performClose(nil)
            return
        }

        let view = SettingsView(viewModel: vm)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 500),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Mac Usage Meter - Settings"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        settingsWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        popover?.performClose(nil)
    }
}
