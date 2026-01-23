#!/bin/bash
#
# Setup daily Docker build cache cleanup at 3 AM
# Creates a LaunchAgent (macOS) to run cleanup daily
#
# Usage:
#   ./setup-build-cache-cleanup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEANUP_SCRIPT="${SCRIPT_DIR}/cleanup-build-cache.sh"
PLIST_NAME="com.tradingagent.docker-build-cache-cleanup"
PLIST_FILE="${HOME}/Library/LaunchAgents/${PLIST_NAME}.plist"

echo "Setting up Docker build cache cleanup schedule (daily at 3 AM)..."

# Create plist content
cat > "${PLIST_FILE}" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_NAME}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${CLEANUP_SCRIPT}</string>
        <string>--older-than-days=7</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>3</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>RunAtLoad</key>
    <false/>
    <key>StandardOutPath</key>
    <string>${SCRIPT_DIR}/build-cache-cleanup.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${SCRIPT_DIR}/build-cache-cleanup.stderr.log</string>
</dict>
</plist>
PLIST_EOF

echo "✓ Created LaunchAgent plist: ${PLIST_FILE}"

# Unload if already loaded
launchctl list | grep -q "${PLIST_NAME}" && {
    echo "Unloading existing agent..."
    launchctl unload "${PLIST_FILE}" 2>/dev/null || true
}

# Load the agent
echo "Loading LaunchAgent..."
launchctl load "${PLIST_FILE}"

echo ""
echo "✓ Docker build cache cleanup scheduled successfully!"
echo ""
echo "Schedule: Daily at 3:00 AM"
echo "Config: Remove cache older than 7 days"
echo "Logs: ${SCRIPT_DIR}/build-cache-cleanup.*.log"
echo ""
echo "To check status:"
echo "  launchctl list | grep ${PLIST_NAME}"
echo ""
echo "To unload (stop scheduled cleanup):"
echo "  launchctl unload ${PLIST_FILE}"
echo ""
echo "To run manually:"
echo "  ${CLEANUP_SCRIPT}"
