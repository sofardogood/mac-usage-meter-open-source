#!/bin/bash
set -euo pipefail

# =============================================================================
# build-and-sign.sh
# SPM ベースで MacUsageMeter と Helper をビルドし、Developer ID で署名する
# =============================================================================

# ---------------------------------------------------------------------------
# 設定変数 — ユーザーが自身の情報に書き換える
# ---------------------------------------------------------------------------
DEVELOPER_ID_APP="${DEVELOPER_ID_APP:-Developer ID Application: YOUR_NAME (TEAM_ID)}"
BUNDLE_ID="com.macusagemeter.MacUsageMeter"
HELPER_BUNDLE_ID="com.macusagemeter.helper"

# プロジェクトルート（このスクリプトの親ディレクトリ）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ビルド設定
CONFIGURATION="release"
BUILD_DIR="${PROJECT_ROOT}/.build/${CONFIGURATION}"
OUTPUT_DIR="${PROJECT_ROOT}/build/release"

# Entitlements パス（存在する場合に使用）
APP_ENTITLEMENTS="${PROJECT_ROOT}/MacUsageMeter/App/MacUsageMeter.entitlements"
HELPER_ENTITLEMENTS="${PROJECT_ROOT}/Helper/Helper.entitlements"

echo "============================================"
echo " MacUsageMeter ビルド & 署名スクリプト"
echo "============================================"
echo ""
echo "プロジェクトルート: ${PROJECT_ROOT}"
echo "署名 ID:           ${DEVELOPER_ID_APP}"
echo ""

# ---------------------------------------------------------------------------
# 1. swift build --configuration release
# ---------------------------------------------------------------------------
echo "[1/5] Release ビルドを実行中..."
cd "${PROJECT_ROOT}"
swift build --configuration "${CONFIGURATION}"
echo "  -> ビルド完了"
echo ""

# ---------------------------------------------------------------------------
# 2. 出力ディレクトリを準備
# ---------------------------------------------------------------------------
echo "[2/5] 出力ディレクトリを準備中..."
rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

# SPM がビルドしたバイナリのパスを検出
# arm64-apple-macosx または x86_64-apple-macosx のどちらか
APP_BINARY=$(find "${PROJECT_ROOT}/.build" -path "*/${CONFIGURATION}/MacUsageMeter" -type f | head -1)
HELPER_BINARY=$(find "${PROJECT_ROOT}/.build" -path "*/${CONFIGURATION}/Helper" -type f | head -1)

if [[ -z "${APP_BINARY}" ]]; then
    echo "エラー: MacUsageMeter バイナリが見つかりません" >&2
    exit 1
fi
if [[ -z "${HELPER_BINARY}" ]]; then
    echo "エラー: Helper バイナリが見つかりません" >&2
    exit 1
fi

echo "  App バイナリ:    ${APP_BINARY}"
echo "  Helper バイナリ: ${HELPER_BINARY}"

# バイナリを出力ディレクトリにコピー
cp "${APP_BINARY}" "${OUTPUT_DIR}/MacUsageMeter"
cp "${HELPER_BINARY}" "${OUTPUT_DIR}/com.macusagemeter.helper"
echo "  -> コピー完了"
echo ""

# ---------------------------------------------------------------------------
# 3. Helper バイナリの署名
#    --options runtime: Hardened Runtime を有効化（Notarization 必須）
#    --force: 既存署名を上書き
#    --timestamp: セキュアタイムスタンプを付与
# ---------------------------------------------------------------------------
echo "[3/5] Helper バイナリを署名中..."
CODESIGN_ARGS=(
    --sign "${DEVELOPER_ID_APP}"
    --identifier "${HELPER_BUNDLE_ID}"
    --options runtime
    --force
    --timestamp
)

# Entitlements ファイルがあれば使用
if [[ -f "${HELPER_ENTITLEMENTS}" ]]; then
    CODESIGN_ARGS+=(--entitlements "${HELPER_ENTITLEMENTS}")
    echo "  Entitlements: ${HELPER_ENTITLEMENTS}"
fi

codesign "${CODESIGN_ARGS[@]}" "${OUTPUT_DIR}/com.macusagemeter.helper"
echo "  -> Helper 署名完了"
echo ""

# ---------------------------------------------------------------------------
# 4. App バイナリの署名
# ---------------------------------------------------------------------------
echo "[4/5] App バイナリを署名中..."
CODESIGN_ARGS=(
    --sign "${DEVELOPER_ID_APP}"
    --identifier "${BUNDLE_ID}"
    --options runtime
    --force
    --timestamp
)

if [[ -f "${APP_ENTITLEMENTS}" ]]; then
    CODESIGN_ARGS+=(--entitlements "${APP_ENTITLEMENTS}")
    echo "  Entitlements: ${APP_ENTITLEMENTS}"
fi

codesign "${CODESIGN_ARGS[@]}" "${OUTPUT_DIR}/MacUsageMeter"
echo "  -> App 署名完了"
echo ""

# ---------------------------------------------------------------------------
# 5. 署名検証
# ---------------------------------------------------------------------------
echo "[5/5] 署名を検証中..."

echo "  Helper:"
codesign --verify --deep --strict --verbose=2 "${OUTPUT_DIR}/com.macusagemeter.helper"
echo "  -> OK"

echo "  App:"
codesign --verify --deep --strict --verbose=2 "${OUTPUT_DIR}/MacUsageMeter"
echo "  -> OK"

echo ""

# 署名情報の表示
echo "--- Helper 署名情報 ---"
codesign -dvv "${OUTPUT_DIR}/com.macusagemeter.helper" 2>&1 || true
echo ""
echo "--- App 署名情報 ---"
codesign -dvv "${OUTPUT_DIR}/MacUsageMeter" 2>&1 || true

echo ""
echo "============================================"
echo " ビルド & 署名完了"
echo " 出力先: ${OUTPUT_DIR}"
echo "============================================"
echo ""
echo "次のステップ: Scripts/notarize.sh を実行して Notarization を行ってください"
