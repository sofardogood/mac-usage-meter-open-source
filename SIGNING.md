# MacUsageMeter 署名・Notarization 手順書

## 前提条件

### 1. Apple Developer Program

- [Apple Developer Program](https://developer.apple.com/programs/) に加入していること（年間 $99）
- Apple ID で [App Store Connect](https://appstoreconnect.apple.com/) にログインできること

### 2. Developer ID 証明書

以下の証明書が Keychain に存在すること:

- **Developer ID Application** — バイナリ・DMG の署名に使用
- **Developer ID Installer** — pkg 形式で配布する場合に使用（本プロジェクトでは DMG を使用するため任意）

#### 証明書の確認方法

```bash
# Keychain にある Developer ID 証明書を一覧表示
security find-identity -v -p codesigning | grep "Developer ID"
```

出力例:

```
1) ABCDEF1234... "Developer ID Application: Your Name (TEAMID123)"
```

この `"Developer ID Application: ..."` の文字列をスクリプトの `DEVELOPER_ID_APP` に設定する。

#### 証明書がない場合

1. Xcode > Settings > Accounts > Manage Certificates
2. 左下の「+」から「Developer ID Application」を作成
3. または [Apple Developer Portal](https://developer.apple.com/account/resources/certificates/list) から CSR を使って手動作成

### 3. Notarization 用の認証情報

`notarytool` で使うための認証情報を Keychain に保存しておく:

```bash
xcrun notarytool store-credentials "notarytool-profile" \
    --apple-id "your-apple-id@example.com" \
    --team-id "TEAMID123" \
    --password "xxxx-xxxx-xxxx-xxxx"
```

`--password` には [App 用パスワード](https://support.apple.com/ja-jp/102654) を使用する（Apple ID のパスワードではない）。

### 4. Xcode Command Line Tools

```bash
xcode-select --install
# または Xcode をインストール済みであれば:
xcode-select -p
# 出力: /Applications/Xcode.app/Contents/Developer
```

---

## SMAuthorizedClients / SMPrivilegedExecutables の設定

MacUsageMeter は Privileged Helper（`com.macusagemeter.helper`）を使用する。
署名時の信頼関係は以下の 2 箇所の plist で定義される。

### Helper/Info.plist — SMAuthorizedClients

Helper 側で「どのアプリからの接続を許可するか」を定義する:

```xml
<key>SMAuthorizedClients</key>
<array>
    <string>identifier "com.macusagemeter.MacUsageMeter" and anchor apple generic and certificate leaf[subject.OU] = "TEAM_ID"</string>
</array>
```

### MacUsageMeter/App/Info.plist — SMPrivilegedExecutables

アプリ側で「どの Helper を信頼するか」を定義する:

```xml
<key>SMPrivilegedExecutables</key>
<dict>
    <key>com.macusagemeter.helper</key>
    <string>identifier "com.macusagemeter.helper" and anchor apple generic and certificate leaf[subject.OU] = "TEAM_ID"</string>
</dict>
```

### 注意事項

- `certificate leaf[subject.OU]` の値は Apple Developer Team ID と完全一致させること
- `Developer ID Application: *` のようなワイルドカード CN は、別 Developer ID による同一 bundle identifier のなりすまし余地を残すため使わないこと
- Xcode ビルドでは `$(DEVELOPMENT_TEAM)` を展開できる。SPM で Info.plist を直接埋め込む場合は、埋め込み前に実 Team ID へ置換すること
- SMJobBless を使用する場合、Helper バイナリに Info.plist を `__TEXT,__info_plist` セクションとして埋め込む必要がある（SPM ビルドでは別途対応が必要）

---

## ビルドから Notarization までの手順

### Step 1: 環境変数の設定

```bash
# 署名 ID を環境変数に設定（スクリプト内のデフォルト値を上書き）
export DEVELOPER_ID_APP="Developer ID Application: Your Name (TEAMID123)"
export KEYCHAIN_PROFILE="notarytool-profile"
export VERSION="1.0.0"
```

### Step 2: ビルドと署名

```bash
./Scripts/build-and-sign.sh
```

このスクリプトが行うこと:
1. `swift build --configuration release` で MacUsageMeter と Helper をビルド
2. Helper バイナリを Developer ID で署名（Hardened Runtime 有効）
3. App バイナリを Developer ID で署名（Hardened Runtime 有効）
4. 署名の検証

成果物は `build/release/` に出力される:
- `build/release/MacUsageMeter` — メインアプリ
- `build/release/com.macusagemeter.helper` — Privileged Helper

### Step 3: Notarization

```bash
./Scripts/notarize.sh
```

このスクリプトが行うこと:
1. 署名済みバイナリを DMG に格納
2. DMG を Developer ID で署名
3. `xcrun notarytool submit` で Apple に送信
4. Notarization 完了まで待機
5. `xcrun stapler staple` で DMG にチケットを埋め込み

成果物は `build/dmg/` に出力される:
- `build/dmg/MacUsageMeter-1.0.0.dmg` — 配布用 DMG

### Step 4: 検証

```bash
# DMG の Notarization 状態を確認
spctl --assess --type open --context context:primary-signature -v build/dmg/MacUsageMeter-*.dmg

# Staple の検証
xcrun stapler validate build/dmg/MacUsageMeter-*.dmg
```

---

## 開発時の Helper インストール・アンインストール

### インストール

```bash
sudo ./Scripts/install-helper.sh
```

Helper バイナリを `/Library/PrivilegedHelperTools/` にコピーし、LaunchDaemon として起動する。

### アンインストール

```bash
sudo ./Scripts/uninstall-helper.sh
```

Helper を停止し、バイナリと plist を削除する。

---

## トラブルシューティング

### 「Developer ID 証明書が見つからない」

```bash
# 利用可能な署名 ID を確認
security find-identity -v -p codesigning
```

証明書がない場合は Xcode の Account 設定から作成するか、Apple Developer Portal で発行する。

### 「Notarization が rejected になる」

```bash
# Notarization のログを確認
xcrun notarytool log <submission-id> --keychain-profile "notarytool-profile"
```

よくある原因:
- **Hardened Runtime が無効**: `--options runtime` を付けて署名しているか確認
- **セキュアタイムスタンプがない**: `--timestamp` を付けて署名しているか確認
- **未署名のライブラリを含んでいる**: すべてのバイナリ・dylib を署名する
- **禁止された entitlement を使用**: `com.apple.security.cs.disable-library-validation` などは Notarization で拒否されることがある

### 「Helper が起動しない」

```bash
# LaunchDaemon の状態を確認
sudo launchctl list com.macusagemeter.helper

# 詳細情報
sudo launchctl print system/com.macusagemeter.helper

# システムログを確認
log show --predicate 'subsystem == "com.apple.xpc" AND category == "connections"' --last 5m
```

よくある原因:
- plist の `ProgramArguments` のパスが間違っている
- Helper バイナリに実行権限がない
- SMAuthorizedClients / SMPrivilegedExecutables の署名要件が一致しない

### 「codesign: resource fork, Finder information, or similar detritus not allowed」

```bash
# 拡張属性を削除
xattr -cr build/release/
```

### 「The signature of the binary is invalid」

```bash
# 詳細な検証エラーを表示
codesign --verify --deep --strict --verbose=4 build/release/MacUsageMeter
```

署名に使った証明書が有効期限切れでないか、Keychain Access で確認する。

### 「xcrun notarytool: credential not found」

Keychain に認証情報が保存されていない。以下で再登録する:

```bash
xcrun notarytool store-credentials "notarytool-profile" \
    --apple-id "your@email.com" \
    --team-id "TEAMID123" \
    --password "xxxx-xxxx-xxxx-xxxx"
```

### SPM ビルドでの Info.plist 埋め込み

SPM（`swift build`）は Xcode と異なり自動で Info.plist をバイナリに埋め込まない。
SMJobBless で Helper を登録する場合、Info.plist を `__TEXT,__info_plist` セクションに埋め込む必要がある:

```bash
# ld のリンカフラグで Info.plist を埋め込む例
swift build -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Helper/Info.plist
```

Package.swift で設定する場合:

```swift
.executableTarget(
    name: "Helper",
    dependencies: ["Shared"],
    path: "Helper",
    linkerSettings: [
        .linkedFramework("CoreWLAN"),
        .linkedFramework("Security"),
        .unsafeFlags([
            "-Xlinker", "-sectcreate",
            "-Xlinker", "__TEXT",
            "-Xlinker", "__info_plist",
            "-Xlinker", "Helper/Info.plist"
        ])
    ]
)
```

> **注意**: `.unsafeFlags` を使うとパッケージが他のパッケージの依存先として使えなくなる。スタンドアロンプロジェクトでのみ使用すること。
