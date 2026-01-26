#!/bin/bash
#
# Setup daily Jenkins workspace cleanup at 2 AM
# Creates a LaunchAgent (macOS) to run cleanup daily
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Jenkins data directory is in storage-infra/jenkins/data (mounted to container)
JENKINS_DATA_DIR="${SCRIPT_DIR}/../storage-infra/jenkins/data"
CLEANUP_SCRIPT="${SCRIPT_DIR}/cleanup-workspace-cron.sh"
LOG_DIR="${SCRIPT_DIR}/logs"
PLIST_NAME="com.tradingagent.jenkins-cleanup"
PLIST_FILE="${HOME}/Library/LaunchAgents/${PLIST_NAME}.plist"

# Create logs directory if it doesn't exist
mkdir -p "${LOG_DIR}"

echo "Setting up Jenkins workspace cleanup schedule (daily at 2 AM)..."
echo "Jenkins data directory: ${JENKINS_DATA_DIR}"
echo "Cleanup script: ${CLEANUP_SCRIPT}"

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
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>JENKINS_DATA_DIR</key>
        <string>${JENKINS_DATA_DIR}</string>
    </dict>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>2</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>RunAtLoad</key>
    <false/>
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/cleanup-cron.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/cleanup-cron.stderr.log</string>
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
echo "✓ Jenkins workspace cleanup scheduled successfully!"
echo ""
echo "Schedule: Daily at 2:00 AM"
echo "Jenkins data directory: ${JENKINS_DATA_DIR}"
echo "Config: Keep workspaces from last 1 day (everything older than yesterday is deleted)"
echo "Logs: ${LOG_DIR}/cleanup-cron.*.log"
echo ""
echo "To check status:"
echo "  launchctl list | grep ${PLIST_NAME}"
echo ""
echo "To unload (stop):"
echo "  launchctl unload ${PLIST_FILE}"
echo ""
echo "To reload after changes:"
echo "  launchctl unload ${PLIST_FILE} && launchctl load ${PLIST_FILE}"
