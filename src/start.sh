#!/bin/bash

#
# @file start.sh
# @author CmPi <cmpi@webe.fr>
# @brief Activate SentryLab systemd services and timers
# @date 2025-12-29
# @version 1.0.362
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

# Check for backup files
BACKUP_DIR="$SCRIPT_DIR/systemd_backup"
has_backup=false
if [ -d "$BACKUP_DIR" ] && ls "$BACKUP_DIR"/*.service >/dev/null 2>&1 || ls "$BACKUP_DIR"/*.timer >/dev/null 2>&1; then
    has_backup=true
fi

# Determine which files to use
SOURCE_DIR="$SYSTEMD_STAGING"
if [ "$has_backup" = true ]; then
    box_begin "Unit Files Available"
    box_line "Default units in: $SYSTEMD_STAGING"
    box_line "Customized backup in: $BACKUP_DIR"
    box_end
    echo
    
    # Ask user which version to install
    box_line "Which version would you like to install?"
    echo
    echo "  1) Default (from staging directory)"
    echo "  2) Customized (from backup directory)"
    echo
    read -p "Enter choice (1 or 2): " choice
    echo
    
    case "$choice" in
        2)
            SOURCE_DIR="$BACKUP_DIR"
            box_line "INFO: Using customized backup units" "GREEN"
            ;;
        1|*)
            SOURCE_DIR="$SYSTEMD_STAGING"
            box_line "INFO: Using default units" "GREEN"
            ;;
    esac
    echo
fi

box_begin "Deploying Systemd Units"
box_value "Source directory" "$SOURCE_DIR"
box_value "Target directory" "$SYSTEMD_LIVE"

# Move service and timer files from staging to live
if ls "$SOURCE_DIR"/*.service >/dev/null 2>&1; then
    cp "$SOURCE_DIR"/*.service "$SYSTEMD_LIVE/"
    chmod 644 "$SYSTEMD_LIVE"/*.service
    box_line "INFO: Services copied and permissions set"
else
    box_line "WARNING: No *.service files found in source"
fi

if ls "$SOURCE_DIR"/*.timer >/dev/null 2>&1; then
    cp "$SOURCE_DIR"/*.timer "$SYSTEMD_LIVE/"
    chmod 644 "$SYSTEMD_LIVE"/*.timer
    box_line "INFO: Timers copied and permissions set"
else
    box_line "WARNING: No *.timer files found in source"
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
