# 開発環境セットアップ

## 前提条件

- Xcode 15 以上
- macOS 13 (Ventura) 以上

### 1. Xcode でプロジェクトを開く

```bash
open Package.swift
```

SPM ベースのプロジェクトなので、Package.swift を直接 Xcode で開けばスキームが自動生成される。

### 2. スキームを MacUsageMeter に変更

Xcode のスキームセレクタで `MacUsageMeter` を選択する。

### 3. Cmd+R で実行

- メニューバーにアイコンが表示される
- セットアップウィザードが起動する
- Helper は未登録のため電力計測は無効（Wi-Fi のみ動作）
- Helper 不在時は `notReady` 状態で起動し、UI は正常に動作する

---

### Helper を使った開発（電力計測を含む完全テスト）

Helper は特権プロセスとして `powermetrics`（root 必要）を実行する。
本番では SMAppService.daemon() で LaunchDaemon として登録するが、
開発時は署名なしのため登録できない。代わりに `--local` モードを使う。

#### 方法 A: dev-setup.sh を使う（推奨）

```bash
# Helper をビルドして sudo で起動する（パスワード入力が必要）
Scripts/dev-setup.sh

# 別のターミナルで XPC 通信テスト
swift run XPCTestClient

# 別のターミナルでアプリを起動
swift run MacUsageMeter
# または Xcode から Cmd+R

# Helper を停止する
Scripts/dev-setup.sh --stop
```

`dev-setup.sh` は以下を行う:
1. `swift build` でプロジェクト全体をビルド
2. 既存のローカル Helper プロセスを停止
3. `sudo .build/debug/Helper --local` でバックグラウンド起動
4. endpoint ファイル (`/tmp/com.macusagemeter.helper.local.endpoint`) の生成を確認

#### 方法 B: 手動で起動

```bash
# ターミナル 1: Helper を起動（sudo が必要）
swift build
sudo .build/debug/Helper --local

# ターミナル 2: XPC テストクライアントで疎通確認
swift run XPCTestClient

# ターミナル 3 (または Xcode): アプリを起動
swift run MacUsageMeter
```

#### 方法 C: run-with-helper.sh を使う

```bash
# Helper とアプリを同時に起動（Ctrl+C で両方停止）
Scripts/run-with-helper.sh
```

### ローカルモードの仕組み

1. `Helper --local` は `NSXPCListener.anonymous()` で XPC リスナーを作成
2. endpoint を `/tmp/com.macusagemeter.helper.local.endpoint` に書き出す
3. `XPCClient.connect()` は endpoint ファイルが存在する場合、自動的にローカル接続を使用
4. DEBUG ビルドでは `XPCPeerValidator` の署名検証がスキップされる

つまり、アプリ側のコード変更は不要。Helper がローカルで起動していれば自動的に接続される。

---

### Helper なしの開発（Wi-Fi のみモード）

Helper が不要な場合（UI 開発、Wi-Fi 計測のみの確認など）:

```bash
# アプリをそのまま起動
swift run MacUsageMeter
# または Xcode から Cmd+R
```

- セットアップウィザードの Step 2 で「スキップして続行」を選択
- Wi-Fi 通信量の計測は `getifaddrs()` を使用するため root 不要
- CollectorController は `notReady` 状態で起動し、Wi-Fi タイマーのみ動作
- 電力データは取得できないが、UI の確認や Wi-Fi 関連の開発は可能

---

### XPC 通信テスト

```bash
# 1. Helper を起動（別ターミナル）
sudo .build/debug/Helper --local

# 2. 全 8 コマンドの E2E テスト実行
swift run XPCTestClient
```

XPCTestClient は以下のコマンドをテストする:
1. PING - 疎通確認
2. GET_SERVICE_STATUS - 登録状態・権限状態
3. GET_CAPABILITIES - 対応機種・利用可能プロファイル
4. REQUEST_POWER_SAMPLE - 電力サンプル取得（root で実行時のみ成功）
5. REQUEST_WIFI_SNAPSHOT - Wi-Fi カウンタ取得
6. RELOAD_PRIVILEGE_STATE - 権限状態再確認
7. COLLECT_HEALTH_REPORT - 診断情報
8. ROTATE_DEBUG_CAPTURE - デバッグ採取切替

---

### ビルド・テスト

```bash
# ビルド
swift build

# テスト
swift test

# UI テストは Xcode から実行する（SPM では XCUITest 非対応）
# open Package.swift -> スキーム MacUsageMeterUITests を選択 -> Cmd+U
```

### 技術メモ

- XPC 接続は全コマンドにタイムアウトが設定されており、Helper 不在でもハングしない
- Collector の起動は非同期で行われ、UI 表示をブロックしない
- Helper 接続に失敗した場合、Collector は `notReady` 状態に遷移し、メンテナンスタイマーのみ起動する
- セットアップウィザードの Helper 登録ステップは、DEBUG ビルドで失敗した場合にローカル開発モードの案内を表示する
