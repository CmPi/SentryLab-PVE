#!/bin/bash

#
# @file start.sh
# @author CmPi <cmpi@webe.fr>
# @brief Activate SentryLab systemd services and timers
# @date 2025-12-29
# @version 1.0
# @usage sudo /usr/local/bin/sentrylab/start.sh
#

set -euo pipefail

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load shared utility functions and configuration
if [ -f "$SCRIPT_DIR/utils.sh" ]; then
    source "$SCRIPT_DIR/utils.sh"
else
    echo "ERROR: Required file '$SCRIPT_DIR/utils.sh' not found." >&2
    exit 1
fi

# Force DEBUG mode for interactive admin tasks
DEBUG=true

SYSTEMD_STAGING="$SCRIPT_DIR/systemd"
SYSTEMD_LIVE="/etc/systemd/system"

box_title "Activating SentryLab Services"

# Verify staging directory exists
if [ ! -d "$SYSTEMD_STAGING" ]; then
    box_line "ERROR: Systemd staging directory not found at $SYSTEMD_STAGING"
    exit 1
fi

box_begin "Deploying Systemd Units"
box_value "Staging directory" "$SYSTEMD_STAGING"
box_value "Target directory" "$SYSTEMD_LIVE"

# Move service and timer files from staging to live
if ls "$SYSTEMD_STAGING"/*.service >/dev/null 2>&1; then
    cp "$SYSTEMD_STAGING"/*.service "$SYSTEMD_LIVE/"
    chmod 644 "$SYSTEMD_LIVE"/*.service
    box_line "INFO: Services copied and permissions set"
else
    box_line "WARNING: No *.service files found in staging"
fi

if ls "$SYSTEMD_STAGING"/*.timer >/dev/null 2>&1; then
    cp "$SYSTEMD_STAGING"/*.timer "$SYSTEMD_LIVE/"
    chmod 644 "$SYSTEMD_LIVE"/*.timer
    box_line "INFO: Timers copied and permissions set"
else
    box_line "WARNING: No *.timer files found in staging"
fi
box_end

box_begin "Systemd Operations"
box_line "Reloading systemd daemon..."
systemctl daemon-reload
box_line "INFO: Daemon reloaded" "GREEN"

# Enable and start services
for service in "$SYSTEMD_LIVE"/sentrylab*.service; do
    if [ -f "$service" ]; then
        service_name=$(basename "$service")
        systemctl enable "$service_name"
        systemctl start "$service_name"
        box_value "Service" "$service_name enabled and started" "GREEN"
    fi
done

# Enable timers
for timer in "$SYSTEMD_LIVE"/sentrylab*.timer; do
    if [ -f "$timer" ]; then
        timer_name=$(basename "$timer")
        systemctl enable "$timer_name"
        systemctl start "$timer_name"
        box_value "Timer" "$timer_name enabled and started" "GREEN"
    fi
done
box_end

echo
box_line "SentryLab services activated successfully" "GREEN"
box_line "Check status: systemctl status sentrylab*.service sentrylab*.timer" "CYAN"
echo
