#!/bin/bash
set -euo pipefail

# =============================================================================
# dev-run.sh
# ビルド -> .app バンドルにコピー -> 起動
#
# 使い方:
#   Scripts/dev-run.sh            # ビルドして LaunchAgent 管理で起動
#   Scripts/dev-run.sh --oneshot  # ビルドして .app を一度だけ起動
#   Scripts/dev-run.sh --kill     # LaunchAgent を解除してアプリを停止
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

APP_BUNDLE="${PROJECT_ROOT}/build/MacUsageMeter.app"
APP_BINARY="${APP_BUNDLE}/Contents/MacOS/MacUsageMeter"
RUN_MODE="launch-agent"

# ---------------------------------------------------------------------------
# 実行中のアプリを停止
# ---------------------------------------------------------------------------
kill_app() {
    if pgrep -f "MacUsageMeter.app" &>/dev/null; then
        echo "[INFO] Stopping running MacUsageMeter..."
        pkill -f "MacUsageMeter.app" 2>/dev/null || true
        sleep 1
    fi
}

# ---------------------------------------------------------------------------
# メイン処理
# ---------------------------------------------------------------------------

case "${1:-}" in
    --kill)
        "${SCRIPT_DIR}/install-app-launch-agent.sh" --uninstall
        echo "Done."
        exit 0
        ;;
    --oneshot)
        RUN_MODE="oneshot"
        ;;
esac

echo "============================================"
echo " Mac Usage Meter - Dev Run"
echo "============================================"
echo ""

# 1. 実行中のアプリを停止
if [[ "${RUN_MODE}" == "launch-agent" ]]; then
    "${SCRIPT_DIR}/install-app-launch-agent.sh" --uninstall >/dev/null 2>&1 || true
else
    kill_app
fi

# 2. ビルド
echo "[1/3] Building (debug)..."
cd "${PROJECT_ROOT}"
swift build 2>&1
echo "  -> Build successful"
echo ""

# 3. .app バンドルにコピー
echo "[2/3] Copying binary to .app bundle..."
BUILD_BINARY=$(find "${PROJECT_ROOT}/.build" -name "MacUsageMeter" -type f -path "*/debug/*" -not -path "*.dSYM*" 2>/dev/null | head -1)

if [[ -z "${BUILD_BINARY}" ]]; then
    echo "[ERROR] MacUsageMeter binary not found." >&2
    exit 1
fi

mkdir -p "$(dirname "${APP_BINARY}")"
cp "${BUILD_BINARY}" "${APP_BINARY}"
echo "  -> Copied to ${APP_BUNDLE}"
echo ""

# 4. 起動
if [[ "${RUN_MODE}" == "launch-agent" ]]; then
    echo "[3/3] Installing and launching via LaunchAgent..."
    "${SCRIPT_DIR}/install-app-launch-agent.sh" --no-build
    echo "  -> LaunchAgent is active"
else
    echo "[3/3] Launching MacUsageMeter.app once..."
    open "${APP_BUNDLE}"
    echo "  -> Launched"
fi
echo ""
echo "To stop and disable KeepAlive: Scripts/dev-run.sh --kill"
