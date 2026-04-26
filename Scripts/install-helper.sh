#!/bin/bash
set -euo pipefail

# =============================================================================
# install-helper.sh
# Privileged Helper を手動でインストールする（開発・テスト用）
# root 権限が必要（sudo で実行すること）
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Helper バイナリのソースパス（ビルド済みの場所）
# build/release にあればそちらを優先、なければ .build から探す
if [[ -f "${PROJECT_ROOT}/build/release/com.macusagemeter.helper" ]]; then
    HELPER_BINARY="${PROJECT_ROOT}/build/release/com.macusagemeter.helper"
elif [[ -f "${PROJECT_ROOT}/.build/release/Helper" ]]; then
    HELPER_BINARY="${PROJECT_ROOT}/.build/release/Helper"
else
    # debug ビルドから探す
    HELPER_BINARY=$(find "${PROJECT_ROOT}/.build" -name "Helper" -type f -path "*/debug/*" | head -1)
fi

HELPER_LABEL="com.macusagemeter.helper"
HELPER_INSTALL_PATH="/Library/PrivilegedHelperTools/${HELPER_LABEL}"
LAUNCHD_PLIST_SRC="${PROJECT_ROOT}/Helper/Launchd.plist"
LAUNCHD_PLIST_DST="/Library/LaunchDaemons/${HELPER_LABEL}.plist"

echo "============================================"
echo " Helper 手動インストール（開発用）"
echo "============================================"
echo ""

# ---------------------------------------------------------------------------
# root 権限チェック
# ---------------------------------------------------------------------------
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "エラー: このスクリプトは root 権限で実行してください" >&2
    echo "  sudo $0" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Helper バイナリの存在確認
# ---------------------------------------------------------------------------
if [[ -z "${HELPER_BINARY}" ]] || [[ ! -f "${HELPER_BINARY}" ]]; then
    echo "エラー: Helper バイナリが見つかりません" >&2
    echo "先にビルドを実行してください:" >&2
    echo "  swift build                       (debug)" >&2
    echo "  Scripts/build-and-sign.sh          (release + 署名)" >&2
    exit 1
fi

echo "ソースバイナリ: ${HELPER_BINARY}"
echo "インストール先: ${HELPER_INSTALL_PATH}"
echo "Launchd plist:  ${LAUNCHD_PLIST_DST}"
echo ""

# ---------------------------------------------------------------------------
# 1. 既存の Helper を停止（ロード済みの場合）
# ---------------------------------------------------------------------------
echo "[1/3] 既存の Helper を停止中..."
if launchctl list "${HELPER_LABEL}" &>/dev/null; then
    launchctl unload "${LAUNCHD_PLIST_DST}" 2>/dev/null || true
    echo "  -> 既存の Helper を停止しました"
else
    echo "  -> 既存の Helper は動作していません（スキップ）"
fi
echo ""

# ---------------------------------------------------------------------------
# 2. ファイルをコピー
#    Helper バイナリ: /Library/PrivilegedHelperTools/ に配置
#    Launchd plist:   /Library/LaunchDaemons/ に配置
# ---------------------------------------------------------------------------
echo "[2/3] ファイルをコピー中..."

# ディレクトリの作成（存在しない場合）
mkdir -p /Library/PrivilegedHelperTools

# Helper バイナリをコピー
cp "${HELPER_BINARY}" "${HELPER_INSTALL_PATH}"
# 実行権限を付与、所有者を root に設定
chmod 544 "${HELPER_INSTALL_PATH}"
chown root:wheel "${HELPER_INSTALL_PATH}"
echo "  -> Helper バイナリをコピーしました"

# Launchd plist をコピー
cp "${LAUNCHD_PLIST_SRC}" "${LAUNCHD_PLIST_DST}"
chmod 644 "${LAUNCHD_PLIST_DST}"
chown root:wheel "${LAUNCHD_PLIST_DST}"
echo "  -> Launchd plist をコピーしました"
echo ""

# ---------------------------------------------------------------------------
# 3. Helper を launchctl でロード（起動）
# ---------------------------------------------------------------------------
echo "[3/3] Helper を起動中..."
launchctl load "${LAUNCHD_PLIST_DST}"

# 起動確認
sleep 1
if launchctl list "${HELPER_LABEL}" &>/dev/null; then
    echo "  -> Helper が正常に起動しました"
else
    echo "  警告: Helper の起動確認に失敗しました" >&2
    echo "  launchctl list ${HELPER_LABEL} で状態を確認してください" >&2
fi

echo ""
echo "============================================"
echo " Helper インストール完了"
echo "============================================"
echo ""
echo "確認コマンド:"
echo "  launchctl list ${HELPER_LABEL}"
echo "  sudo launchctl print system/${HELPER_LABEL}"
