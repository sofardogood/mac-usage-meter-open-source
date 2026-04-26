# powermetrics 実機検証結果

## マシン情報

| 項目 | 値 |
|---|---|
| アーキテクチャ | arm64 (Apple Silicon) |
| CPU | Apple M4 Pro |
| macOS | 26.3.1 (Build 25D771280a) |

## 検証結果

### sudo 実行

`sudo powermetrics --sample-count 1 --sample-rate 1000 -f plist --samplers cpu_power` を試行したが、
CLI 環境で sudo パスワード入力ができないため実行不可。

```
sudo: a terminal is required to read the password
```

**これは想定通りの動作。** 仕様書で Privileged Helper (LaunchDaemon, root) として実行する設計としたのは正しい。

### powermetrics の利用可能性

`powermetrics --help` は正常に出力。以下を確認:
- `-f plist` オプションが利用可能
- `--sample-count` オプションが利用可能
- `--samplers cpu_power` が利用可能
- ヘルプに "estimated power consumed by various SoC subsystems, such as CPU, GPU, ANE" と記載 → Apple Silicon での CPU/GPU/ANE 電力推定が利用可能

### パーサーキーパスの検証状況

| キー | 仕様書の記載 | 検証状態 |
|---|---|---|
| `processor.combined_power` | Apple Silicon, mW | **未検証** (sudo 必要) |
| `processor.cpu_power` | Apple Silicon, mW | **未検証** |
| `processor.gpu_power` | Apple Silicon, mW | **未検証** |
| `processor.ane_power` | Apple Silicon, mW | **未検証** |
| `processor.package_power` | Intel, W | **検証不可** (Intel 機なし) |
| `elapsed_ns` | トップレベル | **未検証** |

### 推奨アクション

1. **開発時**: Helper をローカルに手動インストール (`Scripts/install-helper.sh`) し、XPC 経由で powermetrics を実行してキーパスを検証する
2. **代替**: ターミナルから直接 `sudo powermetrics --sample-count 1 -f plist --samplers cpu_power > sample.plist` を実行し、出力をプロジェクトに保存してパーサーテストに使用する
3. **Intel 検証**: Intel Mac が利用可能な場合、同様の手順で `package_power` キーの存在を確認する

### Apple の公式ドキュメントからの補足

powermetrics のヘルプに以下の注意書きがある:
> Average power values reported by powermetrics are estimated and may be inaccurate - hence they should not be used for any comparison between devices, but can be used to help optimize apps for energy efficiency.

これは仕様書の「概算値であり、実際の請求額とは異なります」という UI 注記と整合する。

---

## フィクスチャベースの検証結果

### テストフィクスチャ一覧

sudo が使えない環境のため、Apple 公式ドキュメントと powermetrics man page に基づいた現実的なテストフィクスチャを作成し、パーサーの統合テストに使用している。

| フィクスチャ | 概要 | 対象 source_level |
|---|---|---|
| `apple_silicon_m4_full.plist` | M4 Pro フル出力 (combined/cpu/gpu/ane_power + clusters + hw_model 等) | A |
| `apple_silicon_partial.plist` | cpu_power のみ (combined_power 欠損) | B |
| `intel_full.plist` | Intel Mac フル出力 (package_power + packages/cores 構造) | A |
| `empty_processor.plist` | processor dict が空 | C |

### 検証内容

`PowerMetricsParserIntegrationTests.swift` で以下を検証:

1. **キーパスの存在と解決**: 各フィクスチャで `processor.combined_power`, `processor.package_power` 等のキーパスが正しく解決されること
2. **単位変換**: Apple Silicon の mW → W 変換 (combined_power: 8500 mW → 8.5 W)、Intel の W 単位がそのまま保持されること
3. **値の妥当な範囲**: Apple Silicon ではアイドル~軽負荷時に 0~100W、Intel では 0~200W の範囲内であること
4. **パーサーの unknown キー無視**: hw_model, kern_osversion, clusters, cstate_residency 等の追加キーが存在してもパースが失敗しないこと
5. **source_level 判定**: combined_power 存在 → A、cpu_power のみ → B、空 → C の判定が正しいこと
6. **missingKeys の一貫性**: 欠損キーが missingKeys 配列に正しく列挙されること

### パーサーキーパスの検証状況 (更新)

| キー | 仕様書の記載 | 検証状態 |
|---|---|---|
| `processor.combined_power` | Apple Silicon, mW | **フィクスチャ検証済** (M4 Pro 模擬) |
| `processor.cpu_power` | Apple Silicon, mW | **フィクスチャ検証済** |
| `processor.gpu_power` | Apple Silicon, mW | **フィクスチャ検証済** |
| `processor.ane_power` | Apple Silicon, mW | **フィクスチャ検証済** |
| `processor.package_power` | Intel, W | **フィクスチャ検証済** (Intel 模擬) |
| `elapsed_ns` | トップレベル | **フィクスチャ検証済** |

> **注**: フィクスチャはドキュメントに基づく模擬データであり、実機出力とのキーパス差異は初回起動時の CapabilityProbe で自動検証される。

---

## CapabilityProbe による実機キーパス自動検証

### 仕組み

Helper (LaunchDaemon) の初回起動時に `CapabilityProbe.probe()` が実行され、以下の処理が自動的に行われる:

1. `powermetrics --sample-count 1 -f plist --samplers cpu_power` を root 権限で単発実行
2. 実際の plist 出力から、存在するキー一覧を抽出
3. パーサーが想定するキー (`combined_power`, `cpu_power`, `gpu_power`, `ane_power`, `package_power`, `elapsed_ns`, `processor`) と比較
4. **差分検出**: 想定キーのうち欠損しているもの (missingKeys) と、想定外のキー (unexpectedKeys) を識別
5. 結果を構造化ログ (`NSLog`) で出力
6. 結果を JSON ファイルとして永続化: `~/Library/Application Support/com.macusagemeter.helper/capability_probe_result.json`

### JSON レポートの内容

```json
{
  "bestSourceLevel": "A",
  "detectedKeys": ["elapsed_ns", "processor", "ane_power", "combined_power", "cpu_power", "gpu_power"],
  "exitCode": 0,
  "hardwareFamily": "apple_silicon",
  "missingKeys": [],
  "osMajorVersion": 26,
  "profileCount": 1,
  "profiles": [
    {
      "expectedMetricKeys": ["combined_power", "cpu_power", "gpu_power", "ane_power", "elapsed_ns"],
      "profileId": "default_apple_silicon",
      "sourceLevel": "A"
    }
  ],
  "rawPlistAvailable": true,
  "timestamp": "2026-03-19T12:00:00Z",
  "unexpectedKeys": ["clusters", "cpu_energy", "gpu_energy", "ane_energy", "combined_energy"]
}
```

### 利点

- **フィクスチャと実機の橋渡し**: 開発時はフィクスチャで網羅的にテストし、デプロイ後は CapabilityProbe が実機の出力を自動検証する
- **OS アップデート対応**: macOS のバージョンアップで powermetrics の出力形式が変更された場合、missingKeys / unexpectedKeys で差分を即座に検知可能
- **デバッグ支援**: JSON レポートを確認することで、ユーザー環境固有の問題を診断可能
