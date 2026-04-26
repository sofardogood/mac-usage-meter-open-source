#!/bin/bash
set -euo pipefail

# =============================================================================
# dev-setup.sh
# ローカル開発環境セットアップ & Helper 起動スクリプト
#
# Helper を launchd に一時登録し、machServiceName ベースで
# XPC 通信テストを行えるようにする。
# powermetrics の実行に root 権限が必要なため、sudo で登録する。
#
# 使い方:
#   Scripts/dev-setup.sh           # Helper をビルドして sudo で起動
#   Scripts/dev-setup.sh --build   # ビルドのみ (Helper は起動しない)
#   Scripts/dev-setup.sh --stop    # 実行中の Helper プロセスを停止
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

MACH_SERVICE="com.macusagemeter.helper"
PLIST_PATH="/Library/LaunchDaemons/${MACH_SERVICE}.plist"
SENTINEL_FILE="/tmp/com.macusagemeter.helper.local.ready"

# ---------------------------------------------------------------------------
# ヘルパー関数
# ---------------------------------------------------------------------------

print_header() {
    echo ""
    echo "============================================"
    echo " Mac Usage Meter - Dev Setup"
    echo "============================================"
    echo ""
}

stop_existing_helper() {
    # launchd から停止・解除
    if sudo launchctl list "${MACH_SERVICE}" &>/dev/null; then
        echo "[INFO] Unloading existing Helper from launchd..."
        sudo launchctl bootout system/"${MACH_SERVICE}" 2>/dev/null || true
        sleep 1
    fi

    # プロセスが残っていれば kill
    local pids
    pids=$(pgrep -f "Helper --local" 2>/dev/null || true)
    if [[ -n "${pids}" ]]; then
        echo "[INFO] Stopping leftover Helper processes..."
        echo "${pids}" | xargs sudo kill 2>/dev/null || true
        sleep 1
    fi

    # sentinel ファイルをクリーンアップ (root 所有の場合があるため sudo)
    sudo rm -f "${SENTINEL_FILE}"
}

build_project() {
    echo "[1/2] Building project (debug)..."
    cd "${PROJECT_ROOT}"
    swift build 2>&1
    echo "  -> Build successful"
    echo ""
}

start_helper() {
    echo "[2/2] Starting Helper via launchd (requires sudo)..."
    echo ""
    echo "  Helper needs root privileges to run powermetrics."
    echo "  You may be prompted for your password."
    echo ""

    # Helper バイナリのパスを検出
    local helper_binary
    helper_binary=$(find "${PROJECT_ROOT}/.build" -name "Helper" -type f -path "*/debug/*" -not -path "*.dSYM*" 2>/dev/null | head -1)

    if [[ -z "${helper_binary}" ]]; then
        echo "[ERROR] Helper binary not found. Run 'swift build' first." >&2
        exit 1
    fi

    # 絶対パスに変換
    helper_binary="$(cd "$(dirname "${helper_binary}")" && pwd)/$(basename "${helper_binary}")"
    echo "  Binary: ${helper_binary}"

    # launchd plist を生成して登録
    echo "  Creating launchd plist..."
    sudo tee "${PLIST_PATH}" > /dev/null << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${MACH_SERVICE}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${helper_binary}</string>
        <string>--local</string>
    </array>
    <key>MachServices</key>
    <dict>
        <key>${MACH_SERVICE}</key>
        <true/>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/com.macusagemeter.helper.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/com.macusagemeter.helper.log</string>
</dict>
</plist>
PLIST

    echo "  Loading into launchd..."
    sudo launchctl bootstrap system "${PLIST_PATH}"

    # Helper が起動するのを待つ (最大5秒)
    local wait_count=0
    while [[ ${wait_count} -lt 10 ]]; do
        if sudo launchctl list "${MACH_SERVICE}" &>/dev/null; then
            break
        fi
        sleep 0.5
        wait_count=$((wait_count + 1))
    done

    # 起動確認
    sleep 1
    if sudo launchctl list "${MACH_SERVICE}" &>/dev/null; then
        local helper_pid
        helper_pid=$(sudo launchctl list "${MACH_SERVICE}" 2>/dev/null | head -1 | awk '{print $1}')
        echo ""
        echo "  -> Helper started successfully (PID: ${helper_pid})"
        echo "  -> MachService: ${MACH_SERVICE}"
        echo "  -> Log: /tmp/com.macusagemeter.helper.log"
        echo ""
        echo "============================================"
        echo " Helper is running via launchd"
        echo "============================================"
        echo ""
        echo " The main app will auto-connect on next restart."
        echo " To restart the main app:"
        echo "   pkill MacUsageMeter; swift run MacUsageMeter"
        echo ""
        echo " To test XPC communication:"
        echo "   swift run XPCTestClient"
        echo ""
        echo " To stop the Helper:"
        echo "   Scripts/dev-setup.sh --stop"
        echo ""

        # Helper ログを表示
        if [[ -f /tmp/com.macusagemeter.helper.log ]]; then
            echo " Helper output:"
            cat /tmp/com.macusagemeter.helper.log
        fi
    else
        echo ""
        echo "[ERROR] Helper failed to start." >&2
        echo "        Check log: /tmp/com.macusagemeter.helper.log" >&2
        if [[ -f /tmp/com.macusagemeter.helper.log ]]; then
            echo ""
            cat /tmp/com.macusagemeter.helper.log
        fi
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# メイン処理
# ---------------------------------------------------------------------------

print_header

case "${1:-}" in
    --stop)
        echo "Stopping Helper..."
        stop_existing_helper
        sudo rm -f "${PLIST_PATH}"
        echo "  -> Done"
        ;;
    --build)
        build_project
        echo "Build complete. To start the Helper:"
        echo "  Scripts/dev-setup.sh"
        ;;
    *)
        stop_existing_helper
        build_project
        start_helper
        ;;
esac
