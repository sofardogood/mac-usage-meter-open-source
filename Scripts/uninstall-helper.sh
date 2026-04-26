#!/bin/bash
set -euo pipefail

# =============================================================================
# uninstall-helper.sh
# Privileged Helper をアンインストールする
# root 権限が必要（sudo で実行すること）
# =============================================================================

HELPER_LABEL="com.macusagemeter.helper"
HELPER_INSTALL_PATH="/Library/PrivilegedHelperTools/${HELPER_LABEL}"
LAUNCHD_PLIST_PATH="/Library/LaunchDaemons/${HELPER_LABEL}.plist"

echo "============================================"
echo " Helper アンインストール"
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
# 1. Helper を停止（launchctl unload）
# ---------------------------------------------------------------------------
echo "[1/3] Helper を停止中..."
if launchctl list "${HELPER_LABEL}" &>/dev/null; then
    launchctl unload "${LAUNCHD_PLIST_PATH}" 2>/dev/null || true
    echo "  -> Helper を停止しました"
else
    echo "  -> Helper は動作していません（スキップ）"
fi
echo ""

# ---------------------------------------------------------------------------
# 2. Helper バイナリを削除
# ---------------------------------------------------------------------------
echo "[2/3] Helper バイナリを削除中..."
if [[ -f "${HELPER_INSTALL_PATH}" ]]; then
    rm -f "${HELPER_INSTALL_PATH}"
    echo "  -> 削除しました: ${HELPER_INSTALL_PATH}"
else
    echo "  -> ファイルが存在しません（スキップ）: ${HELPER_INSTALL_PATH}"
fi
echo ""

# ---------------------------------------------------------------------------
# 3. Launchd plist を削除
# ---------------------------------------------------------------------------
echo "[3/3] Launchd plist を削除中..."
if [[ -f "${LAUNCHD_PLIST_PATH}" ]]; then
    rm -f "${LAUNCHD_PLIST_PATH}"
    echo "  -> 削除しました: ${LAUNCHD_PLIST_PATH}"
else
    echo "  -> ファイルが存在しません（スキップ）: ${LAUNCHD_PLIST_PATH}"
fi
echo ""

# ---------------------------------------------------------------------------
# 確認
# ---------------------------------------------------------------------------
echo "--- アンインストール結果 ---"

# Helper プロセスの残存チェック
if launchctl list "${HELPER_LABEL}" &>/dev/null; then
    echo "  警告: Helper がまだ launchctl に残っています"
    echo "  手動で停止してください: sudo launchctl remove ${HELPER_LABEL}"
else
    echo "  Helper は launchctl から削除されています: OK"
fi

if [[ -f "${HELPER_INSTALL_PATH}" ]]; then
    echo "  警告: バイナリが残っています: ${HELPER_INSTALL_PATH}"
else
    echo "  バイナリは削除されています: OK"
fi

if [[ -f "${LAUNCHD_PLIST_PATH}" ]]; then
    echo "  警告: plist が残っています: ${LAUNCHD_PLIST_PATH}"
else
    echo "  plist は削除されています: OK"
fi

echo ""
echo "============================================"
echo " Helper アンインストール完了"
echo "============================================"
