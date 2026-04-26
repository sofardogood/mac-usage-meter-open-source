# SMAppService.daemon 動作確認チェックリスト

## 1. 開発時のローカルテスト手順 (XPCTestClient)

署名なしで XPC 通信の E2E テストを行う手順。

### 前提条件
- Xcode Command Line Tools がインストール済み
- Swift 5.9 以降
- macOS 13 (Ventura) 以降

### 手順

1. **Helper をローカルモードで起動する** (ターミナル1):
   ```bash
   cd /path/to/mac-usage-meter
   swift build -c debug
   swift run Helper --local
   ```
   以下のような出力が表示される:
   ```
   [Helper] Starting in LOCAL mode (development testing)
   [Helper] Mach service: com.macusagemeter.helper.local
   [Helper] Peer validation: SKIPPED (DEBUG build)
   [Helper] Endpoint written to /tmp/com.macusagemeter.helper.local.endpoint
   [Helper] Waiting for XPC connections...
   ```

2. **XPCTestClient を実行する** (ターミナル2):
   ```bash
   swift run XPCTestClient
   ```

3. **結果を確認する**:
   - 全8コマンドの PASS/FAIL が表示される
   - `REQUEST_POWER_SAMPLE` は sudo なしの場合 fail を期待（PASS として扱う）
   - `REQUEST_WIFI_SNAPSHOT` は Wi-Fi が有効なら success、無効でも通信成功で PASS

4. **powermetrics を含むフルテスト** (オプション):
   ```bash
   swift build -c debug
   sudo .build/debug/Helper --local
   # 別ターミナルで:
   swift run XPCTestClient
   ```

### テスト対象コマンド一覧

| # | コマンド | 期待結果 (非root) | 期待結果 (root) |
|---|---------|------------------|----------------|
| 1 | PING | true | true |
| 2 | GET_SERVICE_STATUS | serviceState=ready | serviceState=ready |
| 3 | GET_CAPABILITIES | hardwareFamily, profiles 表示 | 同左 |
| 4 | REQUEST_POWER_SAMPLE | status=fail (PWR-001) | status=success, avgWatts 値あり |
| 5 | REQUEST_WIFI_SNAPSHOT | status=success (Wi-Fi有効時) | 同左 |
| 6 | RELOAD_PRIVILEGE_STATE | privilegeState=granted | 同左 |
| 7 | COLLECT_HEALTH_REPORT | helperPid, uptimeSec 表示 | 同左 |
| 8 | ROTATE_DEBUG_CAPTURE | currentState=true | 同左 |

---

## 2. 署名済みビルドでの E2E テスト手順

### 前提条件
- Apple Developer ID 証明書
- provisioning profile (Developer ID Application)
- `SIGNING.md` の手順でコード署名設定済み

### 手順

1. **署名済みビルド**:
   ```bash
   # Xcode でビルドするか、xcodebuild を使用
   xcodebuild -scheme MacUsageMeter -configuration Release build
   ```

2. **Helper を launchd に登録**:
   ```bash
   # plist を LaunchDaemons にコピー
   sudo cp com.macusagemeter.helper.plist /Library/LaunchDaemons/
   sudo cp .build/release/Helper /Library/PrivilegedHelperTools/com.macusagemeter.helper

   # 権限設定
   sudo chown root:wheel /Library/LaunchDaemons/com.macusagemeter.helper.plist
   sudo chmod 644 /Library/LaunchDaemons/com.macusagemeter.helper.plist
   sudo chown root:wheel /Library/PrivilegedHelperTools/com.macusagemeter.helper
   sudo chmod 544 /Library/PrivilegedHelperTools/com.macusagemeter.helper

   # launchd にロード
   sudo launchctl load /Library/LaunchDaemons/com.macusagemeter.helper.plist
   ```

3. **SMAppService 経由の登録テスト** (アプリ内):
   ```swift
   import ServiceManagement
   let service = SMAppService.daemon(plistName: "com.macusagemeter.helper.plist")
   try service.register()
   ```

4. **動作確認**:
   - アプリを起動し、popover から各データが表示されることを確認
   - `sudo launchctl list | grep macusagemeter` で Helper が動作中か確認
   - Console.app でログを確認: `subsystem:com.macusagemeter`

5. **アンインストール**:
   ```bash
   sudo launchctl unload /Library/LaunchDaemons/com.macusagemeter.helper.plist
   sudo rm /Library/LaunchDaemons/com.macusagemeter.helper.plist
   sudo rm /Library/PrivilegedHelperTools/com.macusagemeter.helper
   ```

---

## 3. macOS バージョン別 確認ポイント

### macOS 13.3 (Ventura)
- [ ] SMAppService.daemon が利用可能 (macOS 13.0+)
- [ ] `register()` / `unregister()` が正常に動作する
- [ ] Helper の launchd 登録が永続する（再起動後も有効）
- [ ] XPC 接続が正常に確立される
- [ ] audit token ベースの peer 検証が動作する

### macOS 14 (Sonoma)
- [ ] SMAppService の status プロパティが正しい値を返す
- [ ] Login Items の設定画面に Helper が表示される
- [ ] ユーザーが Login Items で無効化した場合の挙動を確認
- [ ] `authorizationStatus` の変化通知が動作する
- [ ] powermetrics の出力フォーマットに変更がないか確認

### macOS 15 (Sequoia)
- [ ] 新しい権限モデルへの対応を確認
- [ ] Gatekeeper の強化された検証との互換性
- [ ] powermetrics の plist 出力キーの差異を確認
- [ ] CoreWLAN API の動作を確認（非推奨警告の有無）
- [ ] プライバシー設定での追加の承認要求の有無

---

## 4. よくある問題と対処法

### Helper が起動しない

**症状**: `launchctl list` に Helper が表示されない、または status が非ゼロ

**原因と対処**:
1. **署名の問題**:
   ```bash
   codesign -dv --verbose=4 /Library/PrivilegedHelperTools/com.macusagemeter.helper
   ```
   - Team ID が正しいか確認
   - provisioning profile が有効期限内か確認

2. **plist の問題**:
   ```bash
   plutil -lint /Library/LaunchDaemons/com.macusagemeter.helper.plist
   ```
   - `MachServices` にサービス名が正しく定義されているか
   - `Label` がバイナリ名と一致しているか

3. **権限の問題**:
   - plist は `root:wheel` で `644`
   - バイナリは `root:wheel` で `544`

4. **ログの確認**:
   ```bash
   log show --predicate 'subsystem == "com.macusagemeter"' --last 5m
   log show --predicate 'process == "launchd" AND eventMessage CONTAINS "macusagemeter"' --last 5m
   ```

### XPC 接続が拒否される

**症状**: `XPC connection invalidated` が発生、proxy が nil

**原因と対処**:
1. **Helper が未起動**:
   ```bash
   sudo launchctl list | grep macusagemeter
   ```
   未起動なら `sudo launchctl load` で起動

2. **MachService 名の不一致**:
   - Helper の `NSXPCListener(machServiceName:)` の名前
   - UI App の `NSXPCConnection(machServiceName:)` の名前
   - plist の `MachServices` ディクショナリのキー
   - 全て `com.macusagemeter.helper` で一致していること

3. **peer 検証の失敗** (Release ビルド):
   - UI App の signing identifier が `com.macusagemeter.MacUsageMeter` であること
   - `XPCPeerValidator.authorizedClientIdentifier` と一致していること
   - DEBUG ビルドでは検証がスキップされるので、Release のみで発生

4. **sandbox の制約**:
   - App Sandbox が有効な場合、XPC Mach service への接続には
     entitlement が必要な場合がある

### powermetrics が動作しない

**症状**: `REQUEST_POWER_SAMPLE` が常に fail

**原因と対処**:
1. **権限不足**: powermetrics は root 権限が必要
   ```bash
   sudo /usr/bin/powermetrics --sample-count 1 -f plist --samplers cpu_power
   ```
   Helper が root で動作しているか確認

2. **SIP (System Integrity Protection)**:
   - powermetrics は SIP が有効でも動作するが、一部のメトリクスが制限される場合がある

3. **仮想環境**:
   - VM 上では powermetrics が限定的な情報しか返さない
   - source_level が B または C になる

### Wi-Fi カウンタが取得できない

**症状**: `REQUEST_WIFI_SNAPSHOT` が NET-001 で失敗

**原因と対処**:
1. **Wi-Fi が無効**: Wi-Fi がオフの場合、インターフェースが見つからない
2. **有線接続のみ**: Wi-Fi インターフェースが存在しない環境
3. **CoreWLAN の権限**: macOS 14+ では Location Services の許可が必要な場合がある
   - System Settings > Privacy & Security > Location Services

### --local モードで接続できない

**症状**: XPCTestClient が endpoint ファイルを読めない

**原因と対処**:
1. **Helper が起動していない**:
   ```bash
   swift run Helper --local
   ```
   が実行中であることを確認

2. **endpoint ファイルが古い**:
   ```bash
   ls -la /tmp/com.macusagemeter.helper.local.endpoint
   ```
   Helper を再起動して新しい endpoint を生成する

3. **Release ビルドで --local を使用**:
   `--local` は DEBUG ビルドでのみ有効。`swift build -c debug` でビルドすること

4. **ビルドエラー**:
   ```bash
   swift build -c debug 2>&1 | head -20
   ```
   Shared モジュールのビルドが成功しているか確認
