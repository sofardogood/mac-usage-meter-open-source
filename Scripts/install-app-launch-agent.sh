#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

LABEL="${LABEL:-com.macusagemeter.app.keepalive}"
DOMAIN="gui/$(id -u)"
APP_BUNDLE="${APP_BUNDLE:-${HOME}/Applications/MacUsageMeter.app}"
APP_BINARY="${APP_BUNDLE}/Contents/MacOS/MacUsageMeter"
PLIST_PATH="${HOME}/Library/LaunchAgents/${LABEL}.plist"
LOG_DIR="${HOME}/Library/Logs/MacUsageMeter"

MODE="install"
BUILD_APP=1

usage() {
    cat <<USAGE
Usage:
  Scripts/install-app-launch-agent.sh [--install] [--no-build]
  Scripts/install-app-launch-agent.sh --uninstall
  Scripts/install-app-launch-agent.sh --status

Installs MacUsageMeter as a user LaunchAgent with KeepAlive=true.
The app bundle is installed to ~/Applications by default, so it keeps working
after VS Code is closed or this project folder is removed.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install)
            MODE="install"
            ;;
        --no-build)
            BUILD_APP=0
            ;;
        --uninstall)
            MODE="uninstall"
            ;;
        --status)
            MODE="status"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

xml_escape() {
    sed \
        -e 's/&/\&amp;/g' \
        -e 's/</\&lt;/g' \
        -e 's/>/\&gt;/g' \
        -e 's/"/\&quot;/g' \
        -e "s/'/\&apos;/g"
}

write_info_plist() {
    local info_plist="${APP_BUNDLE}/Contents/Info.plist"

    mkdir -p "$(dirname "${info_plist}")"
    cat > "${info_plist}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>Mac Usage Meter</string>
    <key>CFBundleExecutable</key>
    <string>MacUsageMeter</string>
    <key>CFBundleIdentifier</key>
    <string>com.macusagemeter.app</string>
    <key>CFBundleName</key>
    <string>Mac Usage Meter</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.3</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

    printf 'APPL????' > "${APP_BUNDLE}/Contents/PkgInfo"
}

build_app_bundle() {
    echo "[1/4] Building MacUsageMeter..."
    cd "${PROJECT_ROOT}"
    swift build

    local build_binary
    build_binary="$(find "${PROJECT_ROOT}/.build" -name "MacUsageMeter" -type f -path "*/debug/*" -not -path "*.dSYM*" | head -1)"
    if [[ -z "${build_binary}" ]]; then
        echo "MacUsageMeter binary not found under .build" >&2
        exit 1
    fi

    mkdir -p "${APP_BUNDLE}/Contents/MacOS"
    cp "${build_binary}" "${APP_BINARY}"
    rm -rf "${APP_BUNDLE}/Contents/_CodeSignature"
    write_info_plist
    echo "  -> ${APP_BUNDLE}"
}

write_launch_agent_plist() {
    mkdir -p "$(dirname "${PLIST_PATH}")" "${LOG_DIR}"

    local escaped_label escaped_binary escaped_stdout escaped_stderr
    escaped_label="$(printf '%s' "${LABEL}" | xml_escape)"
    escaped_binary="$(printf '%s' "${APP_BINARY}" | xml_escape)"
    escaped_stdout="$(printf '%s' "${LOG_DIR}/launchd.out.log" | xml_escape)"
    escaped_stderr="$(printf '%s' "${LOG_DIR}/launchd.err.log" | xml_escape)"

    cat > "${PLIST_PATH}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${escaped_label}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${escaped_binary}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>ThrottleInterval</key>
    <integer>5</integer>
    <key>StandardOutPath</key>
    <string>${escaped_stdout}</string>
    <key>StandardErrorPath</key>
    <string>${escaped_stderr}</string>
</dict>
</plist>
PLIST

    plutil -lint "${PLIST_PATH}" >/dev/null
}

bootout_agent() {
    launchctl bootout "${DOMAIN}/${LABEL}" >/dev/null 2>&1 || true
}

stop_running_app() {
    pkill -f "${APP_BINARY}" >/dev/null 2>&1 || true
    pkill -f "MacUsageMeter.app/Contents/MacOS/MacUsageMeter" >/dev/null 2>&1 || true
    pkill -x "MacUsageMeter" >/dev/null 2>&1 || true
}

install_agent() {
    if [[ "${BUILD_APP}" -eq 1 ]]; then
        build_app_bundle
    elif [[ ! -x "${APP_BINARY}" ]]; then
        echo "App binary is missing or not executable: ${APP_BINARY}" >&2
        exit 1
    else
        rm -rf "${APP_BUNDLE}/Contents/_CodeSignature"
        write_info_plist
    fi

    echo "[2/4] Writing LaunchAgent..."
    write_launch_agent_plist
    echo "  -> ${PLIST_PATH}"

    echo "[3/4] Loading LaunchAgent with KeepAlive..."
    bootout_agent
    stop_running_app
    launchctl bootstrap "${DOMAIN}" "${PLIST_PATH}"
    launchctl enable "${DOMAIN}/${LABEL}"
    launchctl kickstart -k "${DOMAIN}/${LABEL}"

    echo "[4/4] LaunchAgent status..."
    launchctl print "${DOMAIN}/${LABEL}" | sed -n '1,80p'
    echo ""
    echo "MacUsageMeter is now managed by launchd (${LABEL})."
    echo "App bundle: ${APP_BUNDLE}"
    echo "You can close VS Code and remove this project folder after confirming it runs."
}

uninstall_agent() {
    echo "Unloading LaunchAgent..."
    bootout_agent
    rm -f "${PLIST_PATH}"
    stop_running_app
    echo "Removed ${PLIST_PATH}"
}

print_status() {
    if launchctl print "${DOMAIN}/${LABEL}" >/dev/null 2>&1; then
        launchctl print "${DOMAIN}/${LABEL}" | sed -n '1,120p'
    else
        echo "LaunchAgent is not loaded: ${DOMAIN}/${LABEL}"
    fi

    if pgrep -f "${APP_BINARY}" >/dev/null 2>&1; then
        echo ""
        pgrep -fl "${APP_BINARY}"
    elif pgrep -x "MacUsageMeter" >/dev/null 2>&1; then
        echo ""
        pgrep -xlf "MacUsageMeter"
    fi
}

case "${MODE}" in
    install)
        install_agent
        ;;
    uninstall)
        uninstall_agent
        ;;
    status)
        print_status
        ;;
esac
