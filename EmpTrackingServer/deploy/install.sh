#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER_DIR="$(dirname "$SCRIPT_DIR")"
INSTALL_DIR="$HOME/EmpTrackingServer"
LOG_DIR="$HOME/Library/Logs/EmpTracking"
PLIST_NAME="com.emptracking.server"
PLIST_DEST="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"

echo "Building server..."
cd "$SERVER_DIR"
swift build -c release

echo "Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
cp -f ".build/release/App" "$INSTALL_DIR/EmpTrackingServer"
mkdir -p "$LOG_DIR"

echo "Installing LaunchAgent..."
# Stop existing if running
launchctl bootout "gui/$(id -u)/$PLIST_NAME" 2>/dev/null || true

sed -e "s|__BINARY_PATH__|$INSTALL_DIR/EmpTrackingServer|g" \
    -e "s|__LOG_DIR__|$LOG_DIR|g" \
    -e "s|__WORKING_DIR__|$INSTALL_DIR|g" \
    "$SCRIPT_DIR/com.emptracking.server.plist" > "$PLIST_DEST"

launchctl bootstrap "gui/$(id -u)" "$PLIST_DEST"

echo "Done! Server running on http://$(hostname).local:8080"
echo "Logs: $LOG_DIR/server.log"
