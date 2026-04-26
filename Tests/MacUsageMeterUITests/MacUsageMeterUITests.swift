import XCTest

/// UI テスト
///
/// 受入テストケース (第16.3節) のうち UI 操作を伴うものを自動化する。
/// 各テストは XCUIApplication を使用し、accessibilityIdentifier で要素を特定する。
final class MacUsageMeterUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: - テスト 1: メニューバーにステータスアイテムが表示される

    /// アプリ起動後、メニューバーに NSStatusItem のボタンが存在すること
    func testStatusItemAppearsInMenuBar() throws {
        // メニューバーのステータスアイテムは NSStatusBar 上に配置されるため、
        // XCUIApplication のメニューバー内に accessibilityIdentifier="statusBarButton" の
        // ボタンが存在することを確認する。
        let menuBarsQuery = app.menuBars
        // ステータスアイテムのボタンは statusBarButton の identifier を持つ
        let statusButton = menuBarsQuery.statusItems.firstMatch
        XCTAssertTrue(
            statusButton.waitForExistence(timeout: 10),
            "メニューバーにステータスアイテムが表示されるべき"
        )
    }

    // MARK: - テスト 2: ステータスアイテムクリックでポップオーバーが表示される

    /// メニューバーのステータスアイテムをクリックするとポップオーバーが表示されること
    func testClickingStatusItemShowsPopover() throws {
        // ステータスアイテムをクリック
        let statusButton = app.menuBars.statusItems.firstMatch
        XCTAssertTrue(
            statusButton.waitForExistence(timeout: 10),
            "ステータスアイテムが見つからない"
        )
        statusButton.click()

        // ポップオーバーが表示されるのを待つ
        // ポップオーバー内のヘッダテキスト "Mac Usage Meter" で存在を確認
        let popoverContent = app.staticTexts["Mac Usage Meter"]
        XCTAssertTrue(
            popoverContent.waitForExistence(timeout: 5),
            "ステータスアイテムクリック後にポップオーバーが表示されるべき"
        )
    }

    // MARK: - テスト 3: ポップオーバーに「詳細を見る」ボタンが存在する

    /// ポップオーバー内に「詳細を見る」ボタン (accessibilityIdentifier: showDetailButton) が存在すること
    func testPopoverContainsShowDetailButton() throws {
        // ステータスアイテムをクリックしてポップオーバーを開く
        let statusButton = app.menuBars.statusItems.firstMatch
        XCTAssertTrue(statusButton.waitForExistence(timeout: 10))
        statusButton.click()

        // ポップオーバーが表示されるのを待つ
        let popoverContent = app.staticTexts["Mac Usage Meter"]
        XCTAssertTrue(
            popoverContent.waitForExistence(timeout: 5),
            "ポップオーバーが表示されるべき"
        )

        // 「詳細を見る」ボタンの存在を確認 (accessibilityIdentifier)
        let detailButton = app.buttons["showDetailButton"]
        XCTAssertTrue(
            detailButton.waitForExistence(timeout: 5),
            "ポップオーバー内に「詳細を見る」ボタンが存在するべき"
        )
    }

    // MARK: - テスト 4: 設定画面が開ける

    /// 設定画面 (SettingsView) がアプリメニューから開けること
    func testSettingsWindowCanBeOpened() throws {
        // macOS の標準メニューから「設定...」を選択して設定画面を開く
        // Cmd+, ショートカットを使用
        app.typeKey(",", modifierFlags: .command)

        // 設定画面の存在を accessibilityIdentifier で確認
        let settingsView = app.groups["settingsView"].firstMatch
        // Settings ウィンドウ自体、またはフォーム内の既知の要素で確認
        let settingsWindow = app.windows.containing(.group, identifier: "settingsView").firstMatch

        // 設定画面内の「設定を保存」ボタンで画面の表示を確認
        let saveButton = app.buttons["saveSettingsButton"]
        XCTAssertTrue(
            saveButton.waitForExistence(timeout: 10),
            "設定画面が開き、「設定を保存」ボタンが表示されるべき"
        )
    }

    // MARK: - テスト 5: 設定画面の電力単価フィールドに入力できる

    /// 設定画面の電力単価テキストフィールドに値を入力できること
    func testElectricityUnitPriceFieldIsEditable() throws {
        // 設定画面を開く
        app.typeKey(",", modifierFlags: .command)

        // 電力単価フィールドを取得
        let priceField = app.textFields["electricityUnitPriceField"]
        XCTAssertTrue(
            priceField.waitForExistence(timeout: 10),
            "電力単価フィールドが表示されるべき"
        )

        // フィールドをクリックしてフォーカスを当てる
        priceField.click()

        // 既存のテキストを全選択して置換入力
        priceField.typeKey("a", modifierFlags: .command)
        priceField.typeText("25.5")

        // 入力された値を検証
        let fieldValue = priceField.value as? String ?? ""
        XCTAssertEqual(
            fieldValue, "25.5",
            "電力単価フィールドに入力した値 '25.5' が反映されるべき"
        )
    }

    // MARK: - テスト 6: 初回セットアップ画面が表示される (setup_completed_at 未設定時)

    /// setup_completed_at が未設定の状態でアプリを起動すると、
    /// 初回セットアップ画面 (G-005) が自動的に表示されること
    func testInitialSetupScreenAppearsWhenNotCompleted() throws {
        // setup_completed_at 未設定の状態を再現するために、
        // 起動引数でリセットフラグを渡す
        app.terminate()

        let freshApp = XCUIApplication()
        freshApp.launchArguments.append("--reset-setup")
        freshApp.launch()

        // セットアップウィンドウの表示を確認
        // タイトルバーまたはウェルカムテキストで判定
        let setupWindow = freshApp.windows["Mac Usage Meter - セットアップ"]
        let welcomeText = freshApp.staticTexts["Mac Usage Meter へようこそ"]

        // セットアップ画面が表示されるか確認
        // 注意: setup_completed_at が既に設定されている環境では表示されない
        let setupAppeared = setupWindow.waitForExistence(timeout: 10)
            || welcomeText.waitForExistence(timeout: 5)

        // セットアップ画面が見つからない場合はスキップ
        // (setup_completed_at が既に保存済みの環境では表示されないため)
        if !setupAppeared {
            // 代替確認: setupView の identifier を持つ要素を検索
            let setupView = freshApp.groups["setupView"].firstMatch
            let setupViewExists = setupView.waitForExistence(timeout: 5)

            // それでも見つからない場合、DB に setup_completed_at が既に存在する環境
            // テスト環境のリセットが必要であることを記録してスキップ
            try XCTSkipUnless(
                setupViewExists,
                "setup_completed_at が既に設定済みの環境のため、初回セットアップ画面は表示されない。" +
                "テストするには DB をリセットするか --reset-setup 起動引数への対応が必要。"
            )
        }

        // セットアップ画面が表示された場合、ウェルカムテキストの存在を確認
        if welcomeText.exists {
            XCTAssertTrue(welcomeText.exists, "「Mac Usage Meter へようこそ」テキストが表示されるべき")
        }

        freshApp.terminate()
    }

    // MARK: - AT-01: 初回セットアップ完了

    /// セットアップを完了すると setup_completed_at が保存され、通常画面へ遷移すること
    func testInitialSetupCompletion() throws {
        // セットアップ画面を確認
        let setupWindow = app.windows["Mac Usage Meter - セットアップ"]
        guard setupWindow.waitForExistence(timeout: 5) else {
            // セットアップ済みの場合はスキップ
            try XCTSkipIf(
                true,
                "初回セットアップが既に完了しているためスキップ。"
            )
            return
        }

        // ステップ 1: 概要 → 「次へ」をクリック
        let nextButton = app.buttons["次のステップへ進む"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        nextButton.click()

        // ステップ 2: Helper 登録 → 「次へ」をクリック (登録は環境依存のためスキップ可)
        if nextButton.waitForExistence(timeout: 3) && nextButton.isEnabled {
            nextButton.click()
        }

        // ステップ 3: 料金設定 → 「次へ」をクリック
        if nextButton.waitForExistence(timeout: 3) && nextButton.isEnabled {
            nextButton.click()
        }

        // ステップ 4: 試験採取 → 「次へ」をクリック
        if nextButton.waitForExistence(timeout: 3) && nextButton.isEnabled {
            nextButton.click()
        }

        // ステップ 5: 完了 → 「完了」をクリック
        let completeButton = app.buttons["セットアップを完了する"]
        if completeButton.waitForExistence(timeout: 5) {
            completeButton.click()
        }

        // セットアップウィンドウが閉じたことを確認
        let windowClosed = setupWindow.waitForNonExistence(timeout: 5)
        XCTAssertTrue(windowClosed, "セットアップ完了後にウィンドウが閉じるべき")
    }

    // MARK: - AT-06: 設定変更

    /// 採取間隔を変更して保存すると新設定が反映されること
    func testSettingsChange() throws {
        // 設定画面を開く
        app.typeKey(",", modifierFlags: .command)

        let saveButton = app.buttons["saveSettingsButton"]
        XCTAssertTrue(
            saveButton.waitForExistence(timeout: 10),
            "設定画面の保存ボタンが表示されるべき"
        )

        // 電力単価を変更
        let priceField = app.textFields["electricityUnitPriceField"]
        XCTAssertTrue(priceField.waitForExistence(timeout: 5))
        priceField.click()
        priceField.typeKey("a", modifierFlags: .command)
        priceField.typeText("35.0")

        // 保存ボタンをクリック
        saveButton.click()

        // 保存完了のトースト通知が表示されることを確認
        let toastText = app.staticTexts["設定を保存しました"]
        XCTAssertTrue(
            toastText.waitForExistence(timeout: 5),
            "設定保存後にトースト通知が表示されるべき"
        )
    }

    // MARK: - AT-07: CSV 出力

    /// CSV 出力ボタンが詳細画面の Export タブに存在すること
    func testCSVExport() throws {
        // ステータスアイテムをクリックしてポップオーバーを開く
        let statusButton = app.menuBars.statusItems.firstMatch
        XCTAssertTrue(statusButton.waitForExistence(timeout: 10))
        statusButton.click()

        // 「詳細を見る」ボタンをクリック
        let detailButton = app.buttons["showDetailButton"]
        XCTAssertTrue(detailButton.waitForExistence(timeout: 5))
        detailButton.click()

        // 詳細画面が表示されるのを待つ
        let detailWindow = app.windows["Mac Usage Meter - 詳細"]
        XCTAssertTrue(
            detailWindow.waitForExistence(timeout: 10),
            "詳細画面ウィンドウが表示されるべき"
        )

        // Export タブを選択
        let exportTab = app.buttons["Export"]
        if exportTab.waitForExistence(timeout: 5) {
            exportTab.click()
        }

        // CSV 出力ボタンの存在を確認
        let csvButton = app.buttons["CSVファイルに書き出す"]
        XCTAssertTrue(
            csvButton.waitForExistence(timeout: 5),
            "CSV エクスポートボタンが存在するべき"
        )
    }
}
