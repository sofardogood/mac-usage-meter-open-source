# macOS常駐監視アプリ 詳細設計書 完全版 v3.1

## powermetrics 前提 / 実装着手版 / レビュー指摘全補完

| 文書種別 | 詳細設計書（完全版） |
|---|---|
| 対象プロダクト | Mac の消費電力・Wi-Fi 使用量・概算金額を可視化するメニューバー常駐アプリ |
| 対象 OS | macOS 13 以降 |
| 主要前提 | 電力取得の一次ソースは powermetrics。UI は非特権、権限処理は Helper に限定する。 |
| 配布方針 | Developer ID 署名、Hardened Runtime、有効な Notarization を満たした直接配布 |
| 版数 | v3.1 |
| 作成日 | 2026-03-08 |
| 作成者 | OpenAI |

この版で必ず埋めた不足項目<br>機能要件の詳細仕様、更新間隔、設定可能範囲、グラフ期間・スケール、CSV カラム定義を追加。<br>各画面の項目・操作フロー、メニューバーアイコン仕様、欠測表示パターン一覧を追加。<br>SQLite スキーマ、制約、インデックス、マイグレーション方針、パージ仕様を追加。<br>XPC/IPC コマンド完全列挙、JSON Schema 形式のリクエスト / レスポンス構造、タイムアウトとエラー応答を追加。<br>エラーケース一覧、リトライ設計、通知方法、非機能要件、テスト計画、文書管理情報を追加。

0. 文書管理

| 文書の目的 | 開発者がこの文書のみで UI 実装、Collector 実装、Helper 実装、DB 実装、QA 準備に着手できる状態を作る。 |
|---|---|
| 想定読者 | macOS エンジニア、QA、プロダクトオーナー、リリース担当 |
| 文書の位置づけ | 基本設計書ではなく詳細設計書。実装粒度の入出力、異常系、データ設計、通信仕様、配布要件まで含む。 |
| 対象外 | クラウド同期、複数端末統合管理、アプリ別通信量の厳密追跡、外部ワットメーター連携 |

### 0.1 改訂履歴

| 版数 | 日付 | 変更内容 | 作成者 |
|---|---|---|---|
| v1.0 | 2026-03-08 | 初版。基本設計書として作成。 | OpenAI |
| v2.0 | 2026-03-08 | powermetrics 前提、権限分離、配布設計を反映。 | OpenAI |
| v2.2 | 2026-03-08 | 詳細設計版。画面、DB、XPC、異常系の主要項目を追加。 | OpenAI |
| v3.0 | 2026-03-08 | レビュー指摘の不足項目を全補完し、実装着手可能な完全版へ再構成。 | OpenAI |
| v3.1 | 2026-03-08 | G-006 欠測 / エラー状態画面の詳細仕様を追加。既存の欠測表示パターン一覧との対応関係を明記。 | OpenAI |

### 0.2 用語定義

| 用語 | 定義 |
|---|---|
| UI App | メニューバー表示、ポップオーバー、詳細画面、設定、CSV 出力を担当するアプリ本体。非特権で動作する。 |
| Collector Controller | サンプリングのスケジューリング、XPC 呼び出し、保存トリガー、状態管理を担当する内部層。 |
| Privileged Helper | powermetrics 実行とシステム計測を担当する権限付き補助プロセス。 |
| 欠測 | 取得対象値が得られず、計算や表示を成立させられない状態。 |
| stale | 直近サンプルは存在するが鮮度閾値を超えたため最新値として扱えない状態。 |
| ロールアップ | 生サンプルを時間別・日次に再集計して長期保存量を抑える処理。 |

### 0.3 レビュー指摘の反映表

| 不足項目 | 反映先 |
|---|---|
| 1. 機能要件の詳細仕様 | 第4章 機能要件詳細、付録C CSV 仕様 |
| 2. 画面仕様 | 第5章 画面仕様 |
| 3. SQLite スキーマ詳細 | 第8章 データ保存設計、付録B SQL DDL |
| 4. XPC/IPC 通信仕様 | 第9章 XPC/IPC 通信仕様、付録A JSON Schema |
| 5. エラーハンドリング仕様 | 第10章 エラーハンドリング仕様 |
| 6. 非機能要件 | 第11章 非機能要件 |
| 7. テスト計画 | 第12章 テスト計画 |
| 8. 文書管理情報 | 第0章 文書管理 |

1. 目的と適用範囲

本システムは、Mac の消費電力と Wi-Fi 使用量を継続収集し、メニューバーからリアルタイム値、履歴、概算金額、異常状態を可視化するローカル常駐アプリである。電力取得の一次ソースは powermetrics とし、取得できない環境では無理な推定を行わず欠測として扱う。

### 1.1 システム目的

• 利用者が「いまどれだけ使っているか」「今日・今月でどの程度の量と金額感か」を即座に把握できるようにする。

• 権限不足や非対応機種による欠測を曖昧な 0 値で隠さず、理由と対処を提示する。

• 単一端末内で完結する軽量な監視ツールとし、外部クラウド依存を持たせない。

### 1.2 適用範囲

| 区分 | 内容 |
|---|---|
| 対象 | メニューバー常駐、ポップオーバー、履歴画面、設定画面、初回セットアップ、CSV 出力、ローカル DB 保存、ログイン時起動、診断表示 |
| 非対象 | アプリ別通信量の厳密集計、複数端末の一元管理、法人向け管理ポータル、外部メーター連携 |

2. システム概要とアーキテクチャ

アプリは UI App、Collector Controller、Privileged Helper、SQLite Store の 4 層で構成する。UI は非特権を維持し、powermetrics の実行と機種依存差分の吸収は Helper に集約する。

### 2.1 コンポーネント責務

| コンポーネント | 実装候補 | 責務 | 権限 |
|---|---|---|---|
| UI App | SwiftUI + AppKit | メニューバー表示、ポップオーバー、詳細画面、設定、CSV 出力、通知 | 一般 |
| Collector Controller | Swift actor / service | タイマー制御、XPC 呼び出し、状態遷移、保存、ロールアップ開始 | 一般 |
| Privileged Helper | XPC service / LaunchDaemon 系 | powermetrics 実行、Wi-Fi カウンタ取得、能力検出、正規化 | 管理者 |
| SQLite Store | SQLite | 時系列データ、設定、集計、監査ログ、マイグレーション管理 | 一般 |

### 2.2 基本シーケンス

• 起動時に UI App が設定と前回状態を読み込む。

• Collector Controller が Helper の状態を照会し、能力検出結果と権限状態を取得する。

• Collector Controller は設定された間隔で単発サンプル要求を送信し、結果を SQLite に保存する。

• UI は最新キャッシュと DB から値を取得し、5 秒ごとに表示のみ更新する。

• 1 日 1 回、ロールアップとパージ処理を実行する。

3. 設計上の決定事項

| 決定事項 | 内容 | 理由 |
|---|---|---|
| 電力取得一次ソース | powermetrics | macOS で比較的高精度な電力関連指標を取得しやすく、CLI ベースで自動化しやすいため |
| 対象 OS | macOS 13+ | SMAppService による helper / login item 登録を採用しやすいため |
| 金額の扱い | ユーザー設定ベースの概算 | 契約や単価を暗黙推定しないため |
| 保存時刻 | UTC(Epoch ms) | 集計と CSV の整合を保ちやすいため |
| 配布形態 | Developer ID 署名済み DMG を基本 | 社内・外部配布の両立がしやすいため |

設計上の重要な注意<br>powermetrics の出力項目は機種、OS、権限で変わる。実装では capability probe と parser 正規化を必須にする。<br>SMAppService は macOS 13 以降で helper 実行ファイルの登録・制御に使用する公式 API として扱う。<br>Developer ID による外部配布では Hardened Runtime と Notarization をリリース条件に含める。

4. 機能要件詳細

各機能について、動作条件、入出力、初期値、設定可能範囲、正常系・異常系を定義する。

### 4.1 機能一覧

| 機能ID | 機能名 | 優先度 | 概要 |
|---|---|---|---|
| F-001 | 初回セットアップ | Must | 権限説明、初期設定、動作確認をガイド形式で実施する |
| F-002 | ログイン時起動 | Must | ユーザー設定に基づきログイン時起動を有効化する |
| F-003 | 電力サンプリング | Must | powermetrics を用いた電力計測と正規化 |
| F-004 | Wi-Fi サンプリング | Must | Wi-Fi インターフェースのバイト差分取得 |
| F-005 | リアルタイム表示 | Must | メニューバーとポップオーバーへの最新値表示 |
| F-006 | 履歴グラフ | Must | 期間別の推移表示 |
| F-007 | 概算料金計算 | Must | 電力単価と通信契約モデルに基づく概算値計算 |
| F-008 | 欠測 / 異常表示 | Must | 欠測理由と対処の表示 |
| F-009 | CSV エクスポート | Should | 時系列 / 日次集計を CSV で出力 |
| F-010 | 設定管理 | Must | 料金、収集、保持、表示オプションの保存 |
| F-011 | 監査ログ / 診断 | Should | 権限・失敗・解析状況の記録 |
| F-012 | データ保守 | Must | ロールアップ、パージ、マイグレーション |

F-001 初回セットアップ

| 動作条件 | 初回起動時、または setup_completed_at が未設定のとき。 |
|---|---|
| 入力 | ログイン時起動、電力単価、通信契約モデル、保持期間、採取間隔。 |
| 出力 | 設定保存、Helper 登録状態、試験採取結果。 |
| 初期値 | 電力単価 31.0、電力採取 60 秒、Wi-Fi 採取 10 秒、保持期間 90 日。 |
| 設定可能範囲 | 電力単価 0.00〜999.99、保持期間 7〜365 日。 |
| 正常系 | 説明 → 権限付与 → 設定入力 → 単発採取 → 完了。 |
| 異常系 | 権限拒否時はスキップせず未完了状態で終了。再開ボタンを表示。 |

F-002 ログイン時起動

| 動作条件 | 設定画面でトグル変更時。 |
|---|---|
| 入力 | enable_launch_at_login: bool |
| 出力 | SMAppService 状態、監査ログ。 |
| 初期値 | 初回セットアップ時に ON を既定提示。ユーザーが変更可能。 |
| 設定可能範囲 | ON / OFF。 |
| 正常系 | register / unregister を呼び、成功なら UI を更新。 |
| 異常系 | 失敗時は元の状態に戻し、理由を表示。 |

F-003 電力サンプリング

| 動作条件 | Collector の周期実行または手動再試行。 |
|---|---|
| 入力 | sampling_profile_id、timeout_sec、captured_at。 |
| 出力 | avg_watts、source_level、status、parser_status、error_code。 |
| 初期値 | 採取間隔 60 秒、タイムアウト 8 秒。 |
| 設定可能範囲 | 採取間隔 30〜300 秒、タイムアウト 5〜15 秒。 |
| 正常系 | Helper が単発採取し、avg_watts を返却。 |
| 異常系 | タイムアウト、解析失敗、権限不足、非対応機種は status=missing/fail。 |

F-004 Wi-Fi サンプリング

| 動作条件 | Collector の周期実行または状態変化検知時。 |
|---|---|
| 入力 | interface_name、previous_counter、current_counter。 |
| 出力 | sent_bytes_delta、recv_bytes_delta、counter_reset_flag。 |
| 初期値 | 採取間隔 10 秒。 |
| 設定可能範囲 | 採取間隔 5〜60 秒。 |
| 正常系 | 差分が正値ならそのまま保存。 |
| 異常系 | 差分が負値なら reset_flag を立て、そのサンプルは欠測または補正。 |

F-005 リアルタイム表示

| 動作条件 | UI 表示中。 |
|---|---|
| 入力 | 最新サンプル、状態、設定。 |
| 出力 | メニューバー文言、ポップオーバー現在値。 |
| 初期値 | 表示更新間隔 5 秒。 |
| 設定可能範囲 | 固定 5 秒。ユーザー設定対象外。 |
| 正常系 | 鮮度内サンプルを表示。 |
| 異常系 | 鮮度切れは「更新待ち」、欠測は原因別文言。 |

F-006 履歴グラフ

| 動作条件 | 詳細画面の History タブ表示時。 |
|---|---|
| 入力 | 表示期間、対象メトリクス。 |
| 出力 | 折れ線 / 棒グラフ、平均値ラベル。 |
| 初期値 | 期間 24 時間、スケール自動。 |
| 設定可能範囲 | 1 時間、24 時間、7 日、30 日、90 日。スケール 自動 / 固定最大。 |
| 正常系 | 期間に応じて raw / rollup を切替表示。 |
| 異常系 | データ不足時は空状態メッセージを表示。 |

F-007 概算料金計算

| 動作条件 | 表示更新または日次ロールアップ時。 |
|---|---|
| 入力 | power_kwh、wifi_gb、電力単価、通信契約モデル。 |
| 出力 | day_cost_yen、month_cost_yen、coverage_ratio。 |
| 初期値 | 電力単価 31.0、通信は固定月額モデル未設定。 |
| 設定可能範囲 | 固定月額 / 従量 / 上限付き従量。 |
| 正常系 | 契約モデルに従い算出。 |
| 異常系 | 欠測区間がある場合は coverage_ratio を併記。 |

F-008 欠測 / 異常表示

| 動作条件 | error_code または missing 状態検知時。 |
|---|---|
| 入力 | error_code、last_success_at、source_level。 |
| 出力 | バナー、バッジ、ヘルプ文言。 |
| 初期値 | 重大エラーは赤、警告は黄、情報は青のバッジ。 |
| 設定可能範囲 | 色や文言は固定。 |
| 正常系 | 原因別テンプレートに従って表示。 |
| 異常系 | 複数エラー時は最優先度の高いものを主表示。 |

F-009 CSV エクスポート

| 動作条件 | Export タブで出力指示時。 |
|---|---|
| 入力 | export_type、date_from、date_to、output_path。 |
| 出力 | CSV ファイル。 |
| 初期値 | UTF-8 with BOM、CRLF、ヘッダー行あり。 |
| 設定可能範囲 | raw power / raw wifi / daily rollup。 |
| 正常系 | 指定期間のレコードをソートして出力。 |
| 異常系 | 書き込み失敗時は保存先変更を促す。 |

F-010 設定管理

| 動作条件 | 設定画面で変更後保存時。 |
|---|---|
| 入力 | key/value。 |
| 出力 | 保存結果、UI 再反映。 |
| 初期値 | 第5章設定画面定義を参照。 |
| 設定可能範囲 | 項目別バリデーションに従う。 |
| 正常系 | 保存成功時にトースト通知。 |
| 異常系 | 不正値は保存せず項目ごとにメッセージ表示。 |

F-011 監査ログ / 診断

| 動作条件 | 権限操作、失敗、設定変更、保守実行時。 |
|---|---|
| 入力 | event_type、severity、detail_json。 |
| 出力 | audit_events、os.Logger 出力。 |
| 初期値 | info 以上を保存。debug はオプション。 |
| 設定可能範囲 | info / warn / error / debug。 |
| 正常系 | PII を含めず構造化ログで保存。 |
| 異常系 | DB 不可時はファイル保存せず unified logging のみ。 |

F-012 データ保守

| 動作条件 | 1 日 1 回または起動時保守タイミング。 |
|---|---|
| 入力 | retention_days、user_version。 |
| 出力 | 削除件数、ロールアップ件数、migration 結果。 |
| 初期値 | パージ 03:10、保持 90 日、日次ロールアップ 00:10。 |
| 設定可能範囲 | 保持期間 7〜365 日。パージ時刻は固定。 |
| 正常系 | ロールアップ → パージ → VACUUM 条件判定。 |
| 異常系 | migration 失敗時は起動を中断しバックアップ復旧。 |

### 4.2 更新間隔・表示期間・CSV 仕様の要点

| 項目 | 初期値 | 最小 | 最大 | 備考 |
|---|---|---|---|---|
| メニューバー表示更新 | 5 秒 | 固定 | 固定 | 表示のみ更新 |
| 電力採取間隔 | 60 秒 | 30 秒 | 300 秒 | powermetrics 実行間隔 |
| Wi-Fi 採取間隔 | 10 秒 | 5 秒 | 60 秒 | 差分集計間隔 |
| グラフ期間 | 24 時間 | 1 時間 | 90 日 | 1時間/24時間/7日/30日/90日 |
| CSV 文字コード | UTF-8 with BOM | 固定 | 固定 | 改行は CRLF |

5. 画面仕様

各画面の項目、操作フロー、初期値、バリデーション、欠測時表示を定義する。

### 5.1 メニューバーアイコン仕様

| 状態 | アイコン | 表示テキスト | ツールチップ |
|---|---|---|---|
| 通常 | 電力アイコン（通常色） | ⚡ 42W / Wi-Fi 1.2GB | 最新更新時刻と今日の概算金額を表示 |
| 欠測 | 注意アイコン（黄） | 未測定 | 原因: 権限未付与 / 非対応機種 / 更新待ち など |
| 重大エラー | エラーアイコン（赤） | 要確認 | 詳細を開いて対処を確認 |
| 縮退表示 | アイコンのみ | なし | 狭いメニューバー時に利用 |

### 5.2 ポップオーバー画面の全項目定義

| 項目 | 型 | データ源 | 初期表示 | 更新 |
|---|---|---|---|---|
| 現在電力 | 数値 + 単位 | power_samples 最新 | 読み込み中 | 5 秒 |
| 直近平均電力 | 数値 + 単位 | 直近 1 時間の平均 | — | 5 秒 |
| 今日の Wi-Fi 使用量 | 数値 + 単位 | wifi_samples 日次集計 | 0 B | 5 秒 |
| 今日の概算電気代 | 通貨 | daily_rollups | 未計算 | 5 秒 |
| 今日の概算通信費 | 通貨 | daily_rollups | 未計算 | 5 秒 |
| 1 時間ミニグラフ | グラフ | raw samples | 空グラフ | 5 秒 |
| 最終更新時刻 | 日時 | Collector 状態 | — | 5 秒 |
| 状態メッセージ | テキスト | error_code / source_level | 正常 | 変化時 |
| 詳細を見る | ボタン | 固定 | 有効 | 固定 |
| 再試行 | ボタン | 状態依存 | 通常は非表示 | 変化時 |

### 5.3 設定画面の全項目定義

| ラベル | キー | 型 | 初期値 | バリデーション |
|---|---|---|---|---|
| ログイン時に起動 | launch_at_login_enabled | bool | true | なし |
| 電力単価 (円/kWh) | electricity_unit_price_yen | decimal | 31.0 | 0.00〜999.99 |
| 通信契約モデル | network_tariff_model | enum | fixed | fixed / metered / capped_metered |
| 固定月額 (円) | monthly_fee_yen | decimal | 0 | 0.00〜999999.99 |
| GB 単価 (円) | price_per_gb_yen | decimal | 0 | 0.00〜9999.99 |
| 月額上限 (円) | max_monthly_fee_yen | decimal | 0 | 0.00〜999999.99 |
| 電力採取間隔 (秒) | power_sampling_interval_sec | int | 60 | 30〜300 |
| Wi-Fi 採取間隔 (秒) | wifi_sampling_interval_sec | int | 10 | 5〜60 |
| 保持期間 (日) | retention_days | int | 90 | 7〜365 |
| デバッグ採取保存 | debug_capture_enabled | bool | false | なし |
| ログレベル | log_level | enum | info | debug / info / warn / error |

### 5.4 初回セットアップフロー

| ステップ | 名称 | 入力 / 操作 | 完了条件 |
|---|---|---|---|
| 1 | 概要説明 | 監視対象、概算値の注意、必要権限を表示 | 次へ押下 |
| 2 | 権限確認 | Helper 登録と権限承認 | 状態が ready または limited-ready |
| 3 | 料金設定 | 電力単価と通信モデルを入力 | 必須項目が妥当 |
| 4 | 試験採取 | 電力 / Wi-Fi の単発採取を実行 | 少なくとも Wi-Fi 成功、電力は成功または欠測理由確定 |
| 5 | 完了 | 結果と次の行動を表示 | setup_completed_at 保存 |

### 5.5 欠測時の表示パターン一覧

| パターンID | 条件 | 表示文言 | 操作導線 |
|---|---|---|---|
| M-001 | 権限未付与 | 電力計測の権限が未付与です | セットアップを再開 |
| M-002 | Helper 未登録 | 計測ヘルパーを開始できません | 登録を再試行 |
| M-003 | powermetrics 非対応 / 欠測 | この機種または環境では電力値が得られません | ヘルプ表示のみ |
| M-004 | 更新待ち | 最新データを取得中です | 自動更新待ち |
| M-005 | 解析失敗 | 電力データの解析に失敗しました | 再試行 / 診断表示 |
| M-006 | Wi-Fi インターフェース不明 | Wi-Fi インターフェースを特定できません | ネットワーク状態を確認 |
| M-007 | DB 障害 | 保存領域にアクセスできません | 再起動 / 診断表示 |

### 5.6 G-006 欠測 / エラー状態画面の詳細仕様

G-006 は、欠測またはエラー状態が発生したときに原因、影響範囲、直近発生時刻、推奨アクション、再試行導線を提示する専用画面である。ポップオーバー、ローカル通知、設定画面の診断リンクから遷移できる。単なる警告表示ではなく、原因別の復旧操作を明示し、現在の監視継続可否をユーザーが即座に判断できることを目的とする。

| 項目 | 内容 |
|---|---|
| 画面ID | G-006 |
| 画面名 | 欠測 / エラー状態画面 |
| 表示トリガー | 権限未付与、Helper 停止、powermetrics 失敗、DB 障害、Wi-Fi 未接続、stale 継続など |
| 遷移元 | G-002 ポップオーバー、G-004 設定画面、ローカル通知、起動時診断 |
| 主目的 | 原因の明示、影響範囲の説明、推奨アクションの提示、再試行の実行 |
| 表示優先度 | fatal > degraded > stale > informational の順で最上位 1 件を主表示し、他は補足一覧に表示 |
| 閉じ方 | 閉じる、前画面へ戻る、または対処後に自動復帰 |

表示項目は次表の通りとする。状態コードは 5.5 の欠測時表示パターン一覧と対応し、G-006 では追加の診断情報を表示する。

| セクション | 項目 | 型 | 初期値 | 表示ルール |
|---|---|---|---|---|
| ヘッダ | 状態アイコン | icon | warning | fatal は赤、degraded は黄、informational は灰色 |
| ヘッダ | 状態タイトル | text | 問題を確認しています | 状態コードに応じた固定文言を表示 |
| 概要 | 主メッセージ | multiline text | 取得状態を確認中です | 原因と影響範囲を 2〜3 行で説明 |
| 概要 | 発生時刻 | datetime | — | 最初に検知した時刻をローカル表記で表示 |
| 概要 | 最終成功時刻 | datetime | — | 直近正常サンプルがあれば表示 |
| 概要 | 影響範囲 | tag list | — | 電力のみ / Wi-Fi のみ / 両方 / 保存のみ のいずれか |
| 診断 | 状態コード | text | — | M-001 などのユーザー向けコードを表示 |
| 診断 | 内部エラーコード | text | — | E-00x。デバッグログ有効時のみコピー可能 |
| 操作 | 再試行 | button | enabled | retryable=true のときのみ有効 |
| 操作 | セットアップを再開 | button | hidden | 権限未付与または Helper 未登録時のみ表示 |
| 操作 | 設定を開く | button | enabled | 常時表示。G-004 の該当セクションに遷移 |
| 操作 | ログを開く | button | hidden | debug_log_enabled=true のときのみ表示 |
| フッタ | 閉じる | button | enabled | モーダルを閉じて前画面へ戻る |

状態別パネル仕様を以下に定義する。複数状態が同時発生した場合は優先順位の高いものを主表示し、それ以外は「追加で確認された問題」として折りたたみ一覧に表示する。

| 状態コード | タイトル | 主文言 | 主操作 | 通知/自動復帰 |
|---|---|---|---|---|
| M-001 | 権限が必要です | 電力計測に必要な権限が未付与のため、現在の電力を表示できません。 | セットアップを再開 | 通知あり / 権限付与後に自動再試行 |
| M-002 | 計測ヘルパーを開始できません | 権限付き Helper が未登録または開始失敗しています。 | 登録を再試行 | 通知あり / 成功時に復帰通知 |
| M-003 | この環境では電力値を取得できません | powermetrics から必要な値が得られないため、電力表示を無効化しています。 | ヘルプを開く | 通知は初回のみ / 自動復帰なし |
| M-004 | 最新データを取得中です | 起動直後または再試行中のため、まだ最新サンプルが確定していません。 | そのまま待機 | 通知なし / 成功時に自動で閉じてもよい |
| M-005 | データが古くなっています | 直近サンプルの鮮度が閾値を超えました。表示値は参考値です。 | 再試行 | 継続時のみ通知 / 新規サンプル取得で自動復帰 |
| M-006 | データ保存に失敗しました | SQLite への保存に失敗したため、履歴と集計が不完全になる可能性があります。 | 保存先を確認 | 通知あり / 回復後に復帰通知 |
| M-007 | Wi-Fi が接続されていません | アクティブな Wi-Fi インターフェースが見つからないため通信量を更新できません。 | ネットワーク設定を開く | 通知は任意 / 再接続で自動復帰 |

状態優先順位と操作フローは次の通りとする。

| 優先順位 | 条件 | 主表示 | 遷移後の既定操作 |
|---|---|---|---|
| 1 | DB 破損疑い / DB 書込失敗継続 | M-006 | 設定画面の診断セクションを開き、保存先確認を促す |
| 2 | 権限未付与 / Helper 未登録 | M-001 または M-002 | セットアップ再開ボタンを主ボタンにする |
| 3 | powermetrics 異常終了 / 非対応 | M-003 | ヘルプとサポート文言を優先表示 |
| 4 | stale 継続 | M-005 | 再試行ボタンを主ボタンにする |
| 5 | Wi-Fi 未接続 | M-007 | ネットワーク設定を開く導線を表示 |
| 6 | 起動直後の取得待ち | M-004 | 自動更新待ちのみ表示する |

### 5.7 グラフ仕様

| 画面 | 期間 | データ源 | 既定スケール | 補足 |
|---|---|---|---|---|
| ポップオーバー | 1 時間 | raw samples | 自動 | ミニグラフ。点数を間引かない |
| 詳細 History | 24 時間 | raw samples | 自動 | 電力は折れ線、Wi-Fi は積み上げ棒 |
| 詳細 History | 7 日 | daily rollups | 自動 | 日単位の平均 / 合計表示 |
| 詳細 History | 30 日 | daily rollups | 自動 | バー幅固定 |
| 詳細 History | 90 日 | daily rollups | 固定最大 / 自動切替可 | 長期比較用 |

6. 電力取得詳細設計

電力取得は powermetrics を一次ソースとする。ただし出力内容は機種・OS・権限で変化するため、Helper は capability probe と parser 正規化を行う。

### 6.1 Capability Probe

• 起動時と OS 変更検知時に利用可能な powermetrics プロファイルを調べる。

• プロファイル定義は hardware_family、os_major_version、required_privilege、expected_metric_keys を持つ。

• 利用可能プロファイルが 0 件なら source_level=C を返し、UI に非対応または欠測を表示する。

### 6.2 サンプリング仕様

| 項目 | 初期値 | 最小 | 最大 | 備考 |
|---|---|---|---|---|
| 電力採取間隔 | 60 秒 | 30 秒 | 300 秒 | ユーザー設定可能 |
| 実行タイムアウト | 8 秒 | 5 秒 | 15 秒 | 固定値でも可 |
| 鮮度閾値 | 採取間隔×2 | 固定 | 固定 | これを超えると stale |
| 連続失敗でのバックオフ | 2 倍 | 固定 | 最大 10 分 | 3 連続失敗時 |

### 6.3 正規化ルール

• 標準出力を UTF-8 に正規化し、改行差分を吸収する。

• セクション見出しとキー名を内部キーにマップする。

• 単位の異なる数値は内部単位（W）へ変換する。

• avg_watts を主要値とし、補助値は optional として格納する。

• 解析結果には parser_status、missing_keys、source_level を付与する。

### 6.4 データ品質ルール

| ルールID | 条件 | 処理 |
|---|---|---|
| PWR-Q1 | avg_watts < 0 | fail として保存し、表示しない |
| PWR-Q2 | avg_watts > 500 | 保存はするが outlier_flag=1 |
| PWR-Q3 | parser_status=partial かつ avg_watts あり | 電力表示は許可、補助値は欠測 |
| PWR-Q4 | 3 連続タイムアウト | degraded 状態へ遷移し間隔を一時的に延長 |

7. Wi-Fi 使用量取得詳細設計

Wi-Fi 使用量はアクティブな Wi-Fi インターフェースを動的に特定し、その送受信カウンタ差分を積み上げて算出する。

### 7.1 取得仕様

• インターフェース名は動的に特定し、en0 固定にしない。

• 初回サンプルは基準点として保存し、差分値は 0 とする。

• 差分が負値ならカウンタリセット、再起動、復帰直後とみなし reset_flag を立てる。

### 7.2 集計仕様

| 項目 | 初期値 | 最小 | 最大 | 備考 |
|---|---|---|---|---|
| Wi-Fi 採取間隔 | 10 秒 | 5 秒 | 60 秒 | ユーザー設定可能 |
| 日次集計単位 | 当日 00:00〜23:59:59 | 固定 | 固定 | ローカル日付で集計 |
| 月次集計単位 | 月初〜月末 | 固定 | 固定 | ローカル月で集計 |

8. データ保存設計

SQLite を使用する。型定義、制約、インデックス、マイグレーション、保持期間、パージ処理をここで定義する。

### 8.1 DB 方針

| 項目 | 方針 |
|---|---|
| DB パス | ~/Library/Application Support/<bundle-id>/monitor.sqlite3 |
| 保存時刻 | INTEGER(Epoch ms UTC) |
| マイグレーション管理 | PRAGMA user_version を使用。前進のみ。実行前に .bak を作成。 |
| トランザクション | サンプル保存は 1 件 1 トランザクション。ロールアップはバッチトランザクション。 |
| 保持期間既定値 | power_samples / wifi_samples 90 日、daily_rollups 365 日、audit_events 180 日、debug_capture 7 日 |

### 8.2 power_samples

| カラム | 型 | 制約 / 説明 |
|---|---|---|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT |
| captured_at_ms | INTEGER | NOT NULL, INDEX idx_power_samples_captured_at |
| avg_watts | REAL | NULL 許容 |
| sample_duration_sec | INTEGER | NOT NULL |
| source_level | TEXT | NOT NULL CHECK(source_level IN ('A','B','C')) |
| status | TEXT | NOT NULL CHECK(status IN ('success','partial','missing','fail','stale')) |
| parser_status | TEXT | NOT NULL |
| outlier_flag | INTEGER | NOT NULL DEFAULT 0 |
| raw_capture_id | TEXT | NULL |
| error_code | TEXT | NULL |

### 8.2 wifi_samples

| カラム | 型 | 制約 / 説明 |
|---|---|---|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT |
| captured_at_ms | INTEGER | NOT NULL, INDEX idx_wifi_samples_captured_at |
| interface_name | TEXT | NOT NULL |
| sent_bytes_total | INTEGER | NOT NULL |
| recv_bytes_total | INTEGER | NOT NULL |
| sent_bytes_delta | INTEGER | NOT NULL DEFAULT 0 |
| recv_bytes_delta | INTEGER | NOT NULL DEFAULT 0 |
| counter_reset_flag | INTEGER | NOT NULL DEFAULT 0 |
| status | TEXT | NOT NULL |
| error_code | TEXT | NULL |

### 8.2 daily_rollups

| カラム | 型 | 制約 / 説明 |
|---|---|---|
| date_local | TEXT | PRIMARY KEY |
| power_kwh | REAL | NULL 許容 |
| wifi_gb | REAL | NULL 許容 |
| power_cost_yen | REAL | NULL 許容 |
| network_cost_yen | REAL | NULL 許容 |
| coverage_ratio_power | REAL | NOT NULL DEFAULT 0 |
| coverage_ratio_wifi | REAL | NOT NULL DEFAULT 0 |
| computed_at_ms | INTEGER | NOT NULL |

### 8.2 app_settings

| カラム | 型 | 制約 / 説明 |
|---|---|---|
| key | TEXT | PRIMARY KEY |
| value_text | TEXT | NULL |
| value_number | REAL | NULL |
| value_bool | INTEGER | NULL |
| updated_at_ms | INTEGER | NOT NULL |

### 8.2 audit_events

| カラム | 型 | 制約 / 説明 |
|---|---|---|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT |
| occurred_at_ms | INTEGER | NOT NULL, INDEX idx_audit_events_occurred_at |
| event_type | TEXT | NOT NULL |
| severity | TEXT | NOT NULL CHECK(severity IN ('debug','info','warn','error')) |
| component | TEXT | NOT NULL |
| error_code | TEXT | NULL |
| detail_json | TEXT | NULL |

### 8.2 maintenance_log

| カラム | 型 | 制約 / 説明 |
|---|---|---|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT |
| ran_at_ms | INTEGER | NOT NULL |
| job_name | TEXT | NOT NULL |
| result | TEXT | NOT NULL |
| deleted_rows | INTEGER | NOT NULL DEFAULT 0 |
| notes | TEXT | NULL |

### 8.3 マイグレーション方針

• スキーマ変更は連番 SQL またはコードベース migration とし、PRAGMA user_version で管理する。

• 起動時に現在バージョンと DB の user_version を比較し、差分 migration を順次適用する。

• migration 前に DB ファイルを .bak へコピーし、失敗時は自動復旧を試みる。

• 重大失敗時は UI を read-only 診断モードで起動し、再起動を促す。

### 8.4 データ保持期間とパージ仕様

| 対象 | 既定保持 | パージ方式 | 補足 |
|---|---|---|---|
| power_samples | 90 日 | 日次ジョブで古い行を DELETE | 90 日超の raw は削除 |
| wifi_samples | 90 日 | 日次ジョブで DELETE | 長期表示は daily_rollups を使用 |
| daily_rollups | 365 日 | 月次ジョブで DELETE | 必要に応じて延長可 |
| audit_events | 180 日 | 日次ジョブで DELETE | error は 365 日保持オプションあり |
| debug captures | 7 日 | 日次ジョブで DELETE | debug_capture_enabled 時のみ保存 |

9. XPC/IPC 通信仕様

UI App / Collector Controller と Helper 間は XPC で接続する。自由入力コマンドは許可せず、固定コマンドだけを expose する。

### 9.1 コマンド種別の完全列挙

| コマンド | 方向 | 用途 | タイムアウト |
|---|---|---|---|
| PING | App → Helper | 疎通確認 | 1 秒 |
| GET_SERVICE_STATUS | App → Helper | 登録状態、権限状態、最終エラー取得 | 2 秒 |
| GET_CAPABILITIES | App → Helper | 対応機種・利用可能プロファイル取得 | 3 秒 |
| REQUEST_POWER_SAMPLE | App → Helper | 単発電力サンプル取得 | 10 秒 |
| REQUEST_WIFI_SNAPSHOT | App → Helper | 単発 Wi-Fi カウンタ取得 | 3 秒 |
| RELOAD_PRIVILEGE_STATE | App → Helper | 権限状態の再確認 | 2 秒 |
| COLLECT_HEALTH_REPORT | App → Helper | Helper の診断情報取得 | 3 秒 |
| ROTATE_DEBUG_CAPTURE | App → Helper | デバッグ採取の保存切替 | 2 秒 |

### 9.2 共通リクエスト / レスポンス構造

共通リクエスト Envelope<br>{<br>  "requestId": "uuid",<br>  "command": "REQUEST_POWER_SAMPLE",<br>  "sentAtMs": 1760000000000,<br>  "callerVersion": "3.0.0",<br>  "payload": { ... }<br>}

共通レスポンス Envelope<br>{<br>  "requestId": "uuid",<br>  "result": "ok | partial | error",<br>  "errorCode": "PWR-004",<br>  "message": "human readable",<br>  "capturedAtMs": 1760000000500,<br>  "data": { ... }<br>}

### 9.3 JSON Schema 形式の定義

Request Envelope Schema（抜粋）<br>{<br>  "$schema": "https://json-schema.org/draft/2020-12/schema",<br>  "type": "object",<br>  "required": ["requestId", "command", "sentAtMs", "callerVersion", "payload"],<br>  "properties": {<br>    "requestId": {"type": "string", "format": "uuid"},<br>    "command": {"type": "string", "enum": ["PING", "GET_SERVICE_STATUS", "GET_CAPABILITIES", "REQUEST_POWER_SAMPLE", "REQUEST_WIFI_SNAPSHOT", "RELOAD_PRIVILEGE_STATE", "COLLECT_HEALTH_REPORT", "ROTATE_DEBUG_CAPTURE"]},<br>    "sentAtMs": {"type": "integer", "minimum": 0},<br>    "callerVersion": {"type": "string", "minLength": 1},<br>    "payload": {"type": "object"}<br>  }<br>}

REQUEST_POWER_SAMPLE payload Schema（抜粋）<br>{<br>  "type": "object",<br>  "required": ["profileId", "timeoutSec"],<br>  "properties": {<br>    "profileId": {"type": "string", "minLength": 1},<br>    "timeoutSec": {"type": "integer", "minimum": 5, "maximum": 15},<br>    "collectDebugRaw": {"type": "boolean", "default": false}<br>  }<br>}

Power Sample Response data Schema（抜粋）<br>{<br>  "type": "object",<br>  "required": ["status", "sourceLevel", "parserStatus"],<br>  "properties": {<br>    "status": {"type": "string", "enum": ["success", "partial", "missing", "fail", "stale"]},<br>    "sourceLevel": {"type": "string", "enum": ["A", "B", "C"]},<br>    "parserStatus": {"type": "string"},<br>    "avgWatts": {"type": ["number", "null"]},<br>    "sampleDurationSec": {"type": ["integer", "null"]},<br>    "missingKeys": {"type": "array", "items": {"type": "string"}},<br>    "rawCaptureId": {"type": ["string", "null"]}<br>  }<br>}

### 9.4 タイムアウト・リトライ・エラー応答

| コマンド | タイムアウト | リトライ | 失敗応答 |
|---|---|---|---|
| PING | 1 秒 | 0 回 | IPC-001 |
| GET_SERVICE_STATUS | 2 秒 | 1 回 | IPC-002 |
| GET_CAPABILITIES | 3 秒 | 1 回 | IPC-003 |
| REQUEST_POWER_SAMPLE | 10 秒 | 1 回 | PWR-004 / IPC-004 |
| REQUEST_WIFI_SNAPSHOT | 3 秒 | 1 回 | NET-003 / IPC-005 |
| RELOAD_PRIVILEGE_STATE | 2 秒 | 0 回 | AUTH-002 |
| COLLECT_HEALTH_REPORT | 3 秒 | 0 回 | IPC-006 |
| ROTATE_DEBUG_CAPTURE | 2 秒 | 0 回 | DBG-001 |

10. エラーハンドリング仕様

各エラーについて、検知条件、ユーザー通知、内部処理、リトライ方針を定義する。

| エラーコード | 検知条件 | ユーザー通知 | 内部処理 / リトライ |
|---|---|---|---|
| AUTH-001 | 管理者権限取得失敗 | 電力計測の権限が未付与です | 自動リトライなし。セットアップ再開導線を表示 |
| AUTH-002 | 権限状態確認失敗 | 権限状態を確認できません | 5 分後に再確認 |
| HELP-001 | Helper 未登録 / 起動不可 | 計測ヘルパーを開始できません | 1 回だけ再登録を試行 |
| PWR-001 | powermetrics 実行不可 | 電力計測を開始できません | 次周期まで待機、3 回連続で degraded |
| PWR-002 | powermetrics 非対応 / メトリクス欠測 | この環境では電力値が得られません | 自動リトライなし、limited-ready 扱い |
| PWR-003 | パーサー失敗 | 電力データの解析に失敗しました | 次周期で再試行、debug_capture_enabled なら raw 保存 |
| PWR-004 | powermetrics タイムアウト | 電力取得がタイムアウトしました | 次周期で再試行、3 回でバックオフ |
| NET-001 | Wi-Fi インターフェース不明 | Wi-Fi インターフェースを特定できません | 30 秒後に再試行 |
| NET-002 | カウンタ差分負値 | 通信量を一時的に集計できません | そのサンプルを欠測にして次周期へ |
| NET-003 | Wi-Fi スナップショット失敗 | 通信量取得に失敗しました | 次周期で再試行 |
| DB-001 | DB オープン失敗 | 保存領域にアクセスできません | 起動を中断し read-only 診断モードへ |
| DB-002 | 書き込み失敗 | データ保存に失敗しました | 1 回だけ再試行、失敗ならメモリキャッシュへ退避 |
| DB-003 | migration 失敗 | データ形式の更新に失敗しました | バックアップ復旧を試みる |
| IPC-001 | PING 応答なし | 内部通信を確認しています | Helper 再接続を 1 回試行 |
| IPC-004 | XPC で power sample 応答なし | 内部通信が途切れました | 接続再確立後 1 回だけ再試行 |

### 10.1 通知方針

• warn レベルはポップオーバー内バナーで通知し、モーダルは出さない。

• error レベルでユーザー操作が必要な場合のみ詳細画面内に固定パネルを表示する。

• 再試行可能なエラーには「再試行」ボタンを表示し、再試行不可能なものは理由とヘルプを表示する。

11. 非機能要件

| 分類 | 目標値 | 補足 |
|---|---|---|
| CPU 使用率 | 通常監視時に UI App 平均 1.0% 以下、Helper 平均 1.0% 以下 | 採取瞬間の短時間ピークは除く |
| メモリ使用量 | UI App 160MB 以下、Helper 80MB 以下 | 起動後 10 分以内に安定 |
| バッテリー影響 | 8 時間監視で追加消費 3%pt 以内を目標 | MacBook 実機で確認 |
| DB サイズ | 既定保持で 150MB 以下を目標、250MB で警告 | debug capture 無効時 |
| 起動時間 | アプリ起動からメニューバー表示まで 3 秒以内 | cold start |
| ポップオーバー応答 | クリックから 300ms 以内に描画開始 | 最新値は後追い更新可 |
| 設定保存応答 | 保存押下から 200ms 以内に完了通知 | Collector 再読込は非同期 |
| グラフ切替応答 | 90 日表示でも 600ms 以内 | daily_rollups を使用 |

### 11.1 セキュリティ・プライバシー要件

• UI App は root 権限で動作しない。

• Helper は allowlist 化された固定コマンドのみ実行し、任意シェル入力を受け付けない。

• SSID、接続先 IP、閲覧履歴など不要な識別情報は DB や CSV に保存しない。

• 署名、Hardened Runtime、Notarization をリリース必須条件とする。

12. テスト計画

### 12.1 単体テスト対象

| モジュール | 主観点 |
|---|---|
| PowerParser | セクション差分、単位変換、partial 解析 |
| CapabilityProbe | プロファイル選択、非対応時の戻り値 |
| WifiDeltaCalculator | 差分計算、負値検知、reset_flag |
| TariffCalculator | 固定月額 / 従量 / 上限付き従量 |
| SettingsValidator | 数値範囲、enum 妥当性、依存項目 |
| CSVExporter | カラム順、文字コード、改行、欠測値表現 |
| MigrationRunner | user_version 更新、ロールバック、バックアップ復旧 |

### 12.2 統合テスト / 機種別検証

| 観点 | 対象機種 / 環境 | 確認内容 |
|---|---|---|
| 権限フロー | Apple Silicon ノート / Intel ノート | セットアップ完了、権限拒否時の導線 |
| powermetrics 取得 | Apple Silicon / Intel | avg_watts 取得または欠測理由確定 |
| Wi-Fi 集計 | Wi-Fi 接続 / 切断 / 切替 | 差分計算と reset_flag |
| ロールアップ | 90 日相当の擬似データ | 日次集計の整合性と性能 |
| CSV 出力 | 日本語環境 macOS | UTF-8 with BOM で表計算ソフト表示可能 |
| DB migration | 旧バージョン DB | 前進 migration と失敗復旧 |

### 12.3 受入テストケース詳細

| ケースID | 前提 | 手順 | 期待結果 |
|---|---|---|---|
| AT-01 | 初回起動 | セットアップを完了する | setup_completed_at が保存され、通常画面へ遷移 |
| AT-02 | 権限拒否 | 権限承認を拒否する | 未完了状態のまま終了し、再開導線が表示 |
| AT-03 | 正常計測 | 5 分稼働させる | 電力・Wi-Fi の raw sample が蓄積される |
| AT-04 | powermetrics 欠測 | 非対応環境で起動する | 電力は欠測表示、Wi-Fi は継続取得 |
| AT-05 | Wi-Fi 切断 / 再接続 | 接続を切替える | 差分異常が補正され、欠測理由が必要時だけ表示 |
| AT-06 | 設定変更 | 採取間隔を変更して保存 | 新設定が DB と Collector に反映 |
| AT-07 | CSV 出力 | 1 日分を出力 | 定義されたヘッダー順で UTF-8 BOM CSV が出る |
| AT-08 | 長期データ | 90 日相当データを用意し 90 日表示 | 600ms 以内にグラフ描画開始 |
| AT-09 | migration | 旧 user_version DB を起動 | migration 成功または復旧導線表示 |
| AT-10 | Notarized build | 署名済み配布物を別 Mac で起動 | Gatekeeper 通過後に起動できる |

13. 配布・インストール・更新設計

### 13.1 配布方式

• 基本配布物は Developer ID 署名済み DMG とする。

• DMG 内には .app 本体、README、アンインストール手順を含める。

• 初回起動時に必要な helper / login item 登録を案内し、権限説明をセットアップへ統合する。

### 13.2 リリース要件

• アプリ本体と Helper に対する有効なコード署名。

• Hardened Runtime 有効化。

• Apple による Notarization 完了。

• 最小 2 系統の実機で受入テスト完了（Apple Silicon / Intel）。

### 13.3 更新方針

• v1 系では手動更新を基本とし、自動更新機構は後続フェーズで導入判断する。

• 更新時は migration を実行し、失敗時に旧 DB を復旧できることを必須とする。

### 13.4 アンインストール仕様

• UI App の終了後、登録された helper / login item を解除する。

• Application Support 配下の DB、ログ、設定ファイルを削除する。

• アンインストール手順書を配布物に同梱する。

14. オープン事項と決定ログ

| ID | 種別 | 内容 | 現時点の扱い |
|---|---|---|---|
| D-01 | 決定 | 電力取得の一次ソースは powermetrics | 確定 |
| D-02 | 決定 | UI は非特権、権限処理は Helper へ隔離 | 確定 |
| O-01 | 未解決 | App Sandbox 採否 | POC 結果を踏まえて判断 |
| O-02 | 未解決 | 自動更新方式採否 | v1 リリース後に判断 |
| O-03 | 未解決 | 長期保持を 365 日超へ拡張するか | 利用実績を見て判断 |

## 付録A. JSON Schema と DTO 例

GET_SERVICE_STATUS Response data 例<br>{<br>  "serviceState": "ready | limited-ready | not-registered | degraded",<br>  "privilegeState": "granted | denied | unknown",<br>  "lastSuccessAtMs": 1760000000000,<br>  "lastErrorCode": "PWR-004",<br>  "helperVersion": "3.0.0"<br>}

REQUEST_WIFI_SNAPSHOT Response data 例<br>{<br>  "status": "success | missing | fail",<br>  "interfaceName": "en0",<br>  "sentBytesTotal": 123456789,<br>  "recvBytesTotal": 987654321,<br>  "counterResetFlag": false<br>}

## 付録B. SQL DDL（抜粋）

power_samples DDL<br>CREATE TABLE power_samples (<br>  id INTEGER PRIMARY KEY AUTOINCREMENT,<br>  captured_at_ms INTEGER NOT NULL,<br>  avg_watts REAL NULL,<br>  sample_duration_sec INTEGER NOT NULL,<br>  source_level TEXT NOT NULL CHECK(source_level IN ('A','B','C')),<br>  status TEXT NOT NULL CHECK(status IN ('success','partial','missing','fail','stale')),<br>  parser_status TEXT NOT NULL,<br>  outlier_flag INTEGER NOT NULL DEFAULT 0,<br>  raw_capture_id TEXT NULL,<br>  error_code TEXT NULL<br>);<br>CREATE INDEX idx_power_samples_captured_at ON power_samples(captured_at_ms);

wifi_samples DDL<br>CREATE TABLE wifi_samples (<br>  id INTEGER PRIMARY KEY AUTOINCREMENT,<br>  captured_at_ms INTEGER NOT NULL,<br>  interface_name TEXT NOT NULL,<br>  sent_bytes_total INTEGER NOT NULL,<br>  recv_bytes_total INTEGER NOT NULL,<br>  sent_bytes_delta INTEGER NOT NULL DEFAULT 0,<br>  recv_bytes_delta INTEGER NOT NULL DEFAULT 0,<br>  counter_reset_flag INTEGER NOT NULL DEFAULT 0,<br>  status TEXT NOT NULL,<br>  error_code TEXT NULL<br>);<br>CREATE INDEX idx_wifi_samples_captured_at ON wifi_samples(captured_at_ms);

## 付録C. CSV エクスポート定義

| エクスポート種別 | カラム順 | 形式 |
|---|---|---|
| raw_power | captured_at_utc, captured_at_local, avg_watts, sample_duration_sec, source_level, status, parser_status, error_code | UTF-8 with BOM / CRLF / ヘッダーあり |
| raw_wifi | captured_at_utc, captured_at_local, interface_name, sent_bytes_delta, recv_bytes_delta, sent_bytes_total, recv_bytes_total, status, error_code | UTF-8 with BOM / CRLF / ヘッダーあり |
| daily_rollup | date_local, power_kwh, wifi_gb, power_cost_yen, network_cost_yen, coverage_ratio_power, coverage_ratio_wifi, computed_at_utc | UTF-8 with BOM / CRLF / ヘッダーあり |

• 欠測値は空文字で出力し、0 と混同させない。

• 日付は ISO 8601 を使用する。

• 小数はピリオド区切りで出力する。

## 付録D. 参照資料

• Apple Developer Documentation: SMAppService

• Apple Developer Documentation: register()

• Apple Developer Documentation: Hardened Runtime

• Apple Developer Documentation: Notarizing macOS software before distribution

• Energy Efficiency Guide for Mac Apps: Monitoring Energy Usage / Prioritize Work at the Task Level
