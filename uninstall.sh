#!/bin/bash
#
# @file uninstall.sh
# @author CmPi <cmpi@webe.fr>
# @repo https://github.com/CmPi/SentryLab-PVE
# @brief Uninstallation script for SentryLab-PVE
# @date creation 2025-12-30
# @version 1.0.365
# @usage sudo ./uninstall.sh
#

set -uo pipefail

# Color codes
RED='\033[0;31m'
NC='\033[0m' # No Color

# Error handler
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error_exit "This script must be run as root"
fi

CONF_FILE="/usr/local/etc/sentrylab.conf"
DEST_DIR="/usr/local/bin/sentrylab"
AUTO_DIR="/etc/systemd/system"
EXPORT_DIR="/var/lib/sentrylab"

echo "--- SentryLab Uninstallation ---"

# Step 1: Run stop.sh to disable and stop all services/timers
if [[ -f "${DEST_DIR}/stop.sh" ]]; then
    echo "Running stop.sh to disable and stop all services/timers..."
    if ! bash "${DEST_DIR}/stop.sh"; then
        echo -e "${RED}ERROR: stop.sh failed - services may still be running${NC}"
    fi
else
    echo -e "${RED}ERROR: stop.sh not found at ${DEST_DIR}/stop.sh${NC}"
fi

# Step 2: Remove systemd units from /etc/systemd/system
echo "Removing systemd units from ${AUTO_DIR}..."
if ! rm -f "${AUTO_DIR}/sentrylab-"*.{service,timer} 2>/dev/null; then
    echo -e "${RED}WARNING: Failed to remove some systemd units from ${AUTO_DIR}${NC}"
fi
if ! systemctl daemon-reload; then
    echo -e "${RED}WARNING: Failed to reload systemd daemon${NC}"
fi

# Step 3: Remove scripts and backup directory
echo "Removing scripts from ${DEST_DIR}..."
if [[ -d "${DEST_DIR}" ]]; then
    if ! rm -rf "${DEST_DIR}"; then
        error_exit "Failed to remove ${DEST_DIR}"
    fi
else
    echo -e "${RED}WARNING: ${DEST_DIR} does not exist${NC}"
fi

# Step 4: Ask about export/backup directory
if [[ -d "${EXPORT_DIR}" ]]; then
    echo ""
    read -p "Do you want to delete the backup/export directory (${EXPORT_DIR})? [y/N]: " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Removing ${EXPORT_DIR}..."
        if ! rm -rf "${EXPORT_DIR}"; then
            echo -e "${RED}ERROR: Failed to remove ${EXPORT_DIR}${NC}"
        fi
    else
        echo "Keeping ${EXPORT_DIR}"
    fi
fi

# Step 5: Remind about config file
echo ""
echo "--- Uninstallation Complete ---"
echo ""
echo "NOTE: Configuration file NOT removed: ${CONF_FILE}"
echo "If you wish to remove it, run:"
echo "  sudo rm ${CONF_FILE}"
echo ""

