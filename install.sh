#!/bin/bash
#
# @file install.sh
# @author CmPi <cmpi@webe.fr>
# @repo https://github.com/CmPi/SentryLab-PVE
# @brief Root installation script for SentryLab-PVE
# @date 2025-12-28
# @version 1.1.361
# @usage sudo ./install.sh
#

set -euo pipefail

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

CONF_FILE="/usr/local/etc/sentrylab.conf"
DEST_DIR="/usr/local/bin/sentrylab"
AUTO_DIR="/etc/systemd/system"
EXPORT_DIR="/var/lib/sentrylab/csv"

echo "--- SentryLab Installation ---"

# 1. Create Directories
mkdir -p "$DEST_DIR"
mkdir -p "$DEST_DIR/systemd"
mkdir -p "$EXPORT_DIR"

# 2. Deploy Scripts from ./src
echo "Deploying scripts to $DEST_DIR..."
if [ -d "./src" ]; then
    cp ./src/*.sh "$DEST_DIR/"
    chmod 755 "$DEST_DIR"/*.sh
else
    echo "ERROR: ./src directory not found in current path!"
    exit 1
fi

# 3. Deploy Services & Timers to systemd subfolder
echo "Staging systemd services and timers to $DEST_DIR/systemd..."
if [ -d "./src" ]; then
    cp ./src/*.service "$DEST_DIR/systemd/" 2>/dev/null || true
    cp ./src/*.timer "$DEST_DIR/systemd/" 2>/dev/null || true
    chmod 644 "$DEST_DIR/systemd"/*.service "$DEST_DIR/systemd"/*.timer 2>/dev/null || true
else
    echo "ERROR: ./src directory not found for services and timers!"
    exit 1
fi

# 4. Deploy Config (Template)
if [ ! -f "$CONF_FILE" ]; then
    echo "Installing configuration to $CONF_FILE..."
    cp ./sentrylab.conf "$CONF_FILE"
    chmod 600 "$CONF_FILE"
else
    echo "Configuration exists at $CONF_FILE. Skipping overwrite."
fi

echo ""
echo "Installation complete."
echo ""
echo "Next steps:"
echo "  1. Update $CONF_FILE with your settings"
echo "  2. Test in DEBUG mode: DEBUG=true $DEST_DIR/discovery.sh"
echo "  3. When ready, activate services: $DEST_DIR/start.sh"
echo ""
