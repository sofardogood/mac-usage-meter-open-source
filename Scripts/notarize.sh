#!/bin/bash
set -euo pipefail

# =============================================================================
# notarize.sh
# 署名済みバイナリを DMG に格納し、Apple Notarization を実行する
# =============================================================================

# ---------------------------------------------------------------------------
# 設定変数
# ---------------------------------------------------------------------------
DEVELOPER_ID_APP="${DEVELOPER_ID_APP:-Developer ID Application: YOUR_NAME (TEAM_ID)}"
APPLE_ID="${APPLE_ID:-your-apple-id@example.com}"
TEAM_ID="${TEAM_ID:-YOUR_TEAM_ID}"
# App 固有パスワード: Keychain に保存するか環境変数で渡す
# xcrun notarytool store-credentials "notarytool-profile" で事前登録推奨
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-notarytool-profile}"

BUNDLE_ID="com.macusagemeter.MacUsageMeter"
APP_NAME="MacUsageMeter"
VERSION="${VERSION:-1.0.0}"

# パス
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${PROJECT_ROOT}/build/release"
DMG_DIR="${PROJECT_ROOT}/build/dmg"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="${DMG_DIR}/${DMG_NAME}"

echo "============================================"
echo " MacUsageMeter Notarization スクリプト"
echo "============================================"
echo ""

# ---------------------------------------------------------------------------
# 事前チェック: 署名済みバイナリの存在確認
# ---------------------------------------------------------------------------
if [[ ! -f "${OUTPUT_DIR}/MacUsageMeter" ]]; then
    echo "エラー: 署名済みバイナリが見つかりません: ${OUTPUT_DIR}/MacUsageMeter" >&2
    echo "先に Scripts/build-and-sign.sh を実行してください" >&2
    exit 1
fi

if [[ ! -f "${OUTPUT_DIR}/com.macusagemeter.helper" ]]; then
    echo "エラー: 署名済み Helper バイナリが見つかりません: ${OUTPUT_DIR}/com.macusagemeter.helper" >&2
    echo "先に Scripts/build-and-sign.sh を実行してください" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 1. DMG 用のステージングディレクトリを準備
# ---------------------------------------------------------------------------
echo "[1/5] DMG 用ステージングディレクトリを準備中..."
STAGING_DIR="${DMG_DIR}/staging"
rm -rf "${STAGING_DIR}" "${DMG_PATH}"
mkdir -p "${STAGING_DIR}"

# バイナリをステージングにコピー
cp "${OUTPUT_DIR}/MacUsageMeter" "${STAGING_DIR}/"
cp "${OUTPUT_DIR}/com.macusagemeter.helper" "${STAGING_DIR}/"

# Info.plist と Launchd.plist も同梱
cp "${PROJECT_ROOT}/MacUsageMeter/App/Info.plist" "${STAGING_DIR}/Info.plist"
cp "${PROJECT_ROOT}/Helper/Info.plist" "${STAGING_DIR}/HelperInfo.plist"
cp "${PROJECT_ROOT}/Helper/Launchd.plist" "${STAGING_DIR}/com.macusagemeter.helper.plist"

echo "  -> ステージング完了"
echo ""

# ---------------------------------------------------------------------------
# 2. DMG 作成
#    hdiutil で読み取り専用の圧縮 DMG を生成する
# ---------------------------------------------------------------------------
echo "[2/5] DMG を作成中..."
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${STAGING_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}"
echo "  -> DMG 作成完了: ${DMG_PATH}"
echo ""

# ステージングディレクトリをクリーンアップ
rm -rf "${STAGING_DIR}"

# ---------------------------------------------------------------------------
# 3. DMG 署名
# ---------------------------------------------------------------------------
echo "[3/5] DMG を署名中..."
codesign \
    --sign "${DEVELOPER_ID_APP}" \
    --timestamp \
    --force \
    "${DMG_PATH}"
echo "  -> DMG 署名完了"
echo ""

# ---------------------------------------------------------------------------
# 4. Notarization 送信 & 待機
#    xcrun notarytool を使用（Xcode 13+ 必須）
#    事前に認証情報を Keychain に保存しておくこと:
#      xcrun notarytool store-credentials "notarytool-profile" \
#        --apple-id "your@email.com" \
#        --team-id "TEAM_ID" \
#        --password "app-specific-password"
# ---------------------------------------------------------------------------
echo "[4/5] Notarization を送信中..."
echo "  DMG: ${DMG_PATH}"
echo "  Keychain プロファイル: ${KEYCHAIN_PROFILE}"
echo ""

# submit と wait を一括で実行
xcrun notarytool submit "${DMG_PATH}" \
    --keychain-profile "${KEYCHAIN_PROFILE}" \
    --wait

echo ""
echo "  -> Notarization 完了"
echo ""

# ---------------------------------------------------------------------------
# 5. Staple（DMG に Notarization チケットを埋め込む）
#    これにより、オフラインでも Gatekeeper がチケットを検証できる
# ---------------------------------------------------------------------------
echo "[5/5] Staple を実行中..."
xcrun stapler staple "${DMG_PATH}"
echo "  -> Staple 完了"
echo ""

# ---------------------------------------------------------------------------
# 検証
# ---------------------------------------------------------------------------
echo "--- Staple 検証 ---"
xcrun stapler validate "${DMG_PATH}"
echo ""

echo "--- spctl 検証 ---"
spctl --assess --type open --context context:primary-signature -v "${DMG_PATH}" 2>&1 || true
echo ""

echo "============================================"
echo " Notarization 完了"
echo " DMG: ${DMG_PATH}"
echo "============================================"
echo ""
echo "配布準備完了です。DMG をユーザーに配布できます。"
