#!/bin/bash
# 開発時にHelperをsudoで起動し、アプリと連携するスクリプト
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Building..."
swift build 2>&1

echo "Starting Helper with root privileges..."
echo "Password is required for powermetrics access."

# Helper をローカルモードで起動（バックグラウンド）
sudo .build/debug/Helper --local &
HELPER_PID=$!
echo "Helper started (PID: $HELPER_PID)"

sleep 2

# アプリをバンドルとして起動
cp .build/debug/MacUsageMeter build/MacUsageMeter.app/Contents/MacOS/MacUsageMeter
open build/MacUsageMeter.app

echo ""
echo "=== Mac Usage Meter is running ==="
echo "Helper PID: $HELPER_PID"
echo "Press Ctrl+C to stop"
echo ""

# Ctrl+C で両方停止
trap "echo 'Stopping...'; sudo kill $HELPER_PID 2>/dev/null; pkill -f MacUsageMeter 2>/dev/null; echo 'Done.'" EXIT
wait $HELPER_PID
