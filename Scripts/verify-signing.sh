#!/bin/bash
set -euo pipefail

# =============================================================================
# verify-signing.sh
# MacUsageMeter と Helper の署名・Gatekeeper 検証を行う
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${PROJECT_ROOT}/build/release"

APP_PATH="${OUTPUT_DIR}/MacUsageMeter"
HELPER_PATH="${OUTPUT_DIR}/com.macusagemeter.helper"

PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# ヘルパー関数
# ---------------------------------------------------------------------------
check() {
    local label="$1"
    shift
    echo -n "  [検証] ${label}... "
    if "$@" > /dev/null 2>&1; then
        echo "OK"
        PASS=$((PASS + 1))
    else
        echo "FAIL"
        FAIL=$((FAIL + 1))
    fi
}

# ---------------------------------------------------------------------------
# バイナリ存在確認
# ---------------------------------------------------------------------------
echo "============================================"
echo " MacUsageMeter 署名検証"
echo "============================================"
echo ""

if [[ ! -f "${APP_PATH}" ]]; then
    echo "エラー: App バイナリが見つかりません: ${APP_PATH}" >&2
    echo "先に Scripts/build-and-sign.sh を実行してください" >&2
    exit 1
fi
if [[ ! -f "${HELPER_PATH}" ]]; then
    echo "エラー: Helper バイナリが見つかりません: ${HELPER_PATH}" >&2
    echo "先に Scripts/build-and-sign.sh を実行してください" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 1. codesign --verify
# ---------------------------------------------------------------------------
echo "[1/4] codesign --verify（署名の整合性）"
check "App 署名検証" codesign --verify --deep --strict "${APP_PATH}"
check "Helper 署名検証" codesign --verify --deep --strict "${HELPER_PATH}"
echo ""

# ---------------------------------------------------------------------------
# 2. codesign -d --requirements -（署名要件の表示）
# ---------------------------------------------------------------------------
echo "[2/4] 署名要件の表示"
echo ""
echo "  --- App requirements ---"
codesign -d --requirements - "${APP_PATH}" 2>&1 || true
echo ""
echo "  --- Helper requirements ---"
codesign -d --requirements - "${HELPER_PATH}" 2>&1 || true
echo ""

# ---------------------------------------------------------------------------
# 3. spctl --assess（Gatekeeper 検証）
# ---------------------------------------------------------------------------
echo "[3/4] spctl --assess（Gatekeeper 検証）"
echo -n "  [検証] App Gatekeeper... "
if spctl --assess --type execute "${APP_PATH}" 2>/dev/null; then
    echo "OK"
    PASS=$((PASS + 1))
else
    echo "FAIL (Developer ID 署名が無い場合は正常)"
    FAIL=$((FAIL + 1))
fi

echo -n "  [検証] Helper Gatekeeper... "
if spctl --assess --type execute "${HELPER_PATH}" 2>/dev/null; then
    echo "OK"
    PASS=$((PASS + 1))
else
    echo "FAIL (Developer ID 署名が無い場合は正常)"
    FAIL=$((FAIL + 1))
fi
echo ""

# ---------------------------------------------------------------------------
# 4. 署名情報の詳細表示と相互参照の確認
# ---------------------------------------------------------------------------
echo "[4/4] 署名情報の詳細 & 相互参照"
echo ""
echo "  --- App 署名詳細 ---"
codesign -dvv "${APP_PATH}" 2>&1 || true
echo ""
echo "  --- Helper 署名詳細 ---"
codesign -dvv "${HELPER_PATH}" 2>&1 || true
echo ""

# App の Info.plist の SMPrivilegedExecutables と Helper の SMAuthorizedClients の整合性確認
echo "  --- 相互参照チェック ---"
APP_PLIST="${PROJECT_ROOT}/MacUsageMeter/App/Info.plist"
HELPER_PLIST="${PROJECT_ROOT}/Helper/Info.plist"

echo -n "  [検証] App Info.plist に SMPrivilegedExecutables が存在... "
if /usr/libexec/PlistBuddy -c "Print :SMPrivilegedExecutables" "${APP_PLIST}" > /dev/null 2>&1; then
    echo "OK"
    PASS=$((PASS + 1))
    echo "    値: $(/usr/libexec/PlistBuddy -c "Print :SMPrivilegedExecutables:com.macusagemeter.helper" "${APP_PLIST}" 2>/dev/null || echo '(読み取り失敗)')"
else
    echo "FAIL"
    FAIL=$((FAIL + 1))
fi

echo -n "  [検証] Helper Info.plist に SMAuthorizedClients が存在... "
if /usr/libexec/PlistBuddy -c "Print :SMAuthorizedClients" "${HELPER_PLIST}" > /dev/null 2>&1; then
    echo "OK"
    PASS=$((PASS + 1))
    echo "    値: $(/usr/libexec/PlistBuddy -c "Print :SMAuthorizedClients:0" "${HELPER_PLIST}" 2>/dev/null || echo '(読み取り失敗)')"
else
    echo "FAIL"
    FAIL=$((FAIL + 1))
fi

# Bundle ID の一致確認
echo -n "  [検証] Helper Bundle ID が com.macusagemeter.helper... "
HELPER_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "${HELPER_PLIST}" 2>/dev/null || echo "")
if [[ "${HELPER_BUNDLE_ID}" == "com.macusagemeter.helper" ]]; then
    echo "OK"
    PASS=$((PASS + 1))
else
    echo "FAIL (実際の値: ${HELPER_BUNDLE_ID})"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "============================================"
echo " 検証結果: ${PASS} passed / ${FAIL} failed"
echo "============================================"

if [[ ${FAIL} -gt 0 ]]; then
    echo ""
    echo "注意: Gatekeeper (spctl) の検証は、有効な Developer ID 署名が"
    echo "適用されている場合にのみ成功します。ad-hoc 署名ではFAILになります。"
    exit 1
fi
