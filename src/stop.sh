#!/bin/bash

#
# @file stop.sh
# @author CmPi <cmpi@webe.fr>
# @brief Deactivate SentryLab systemd services and timers
# @date 2025-12-29
# @version 1.0.362
# @usage sudo /usr/local/bin/sentrylab/stop.sh
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

box_title "Deactivating SentryLab Services"

box_begin "Stopping Systemd Units"

# Stop and disable services
disabled_count=0
for service in "$SYSTEMD_LIVE"/sentrylab*.service; do
    if [ -f "$service" ]; then
        service_name=$(basename "$service")
        systemctl stop "$service_name" 2>/dev/null || true
        systemctl disable "$service_name" 2>/dev/null || true
        box_value "Service" "$service_name stopped and disabled" "YELLOW"
        ((disabled_count++))
    fi
done

# Stop and disable timers
for timer in "$SYSTEMD_LIVE"/sentrylab*.timer; do
    if [ -f "$timer" ]; then
        timer_name=$(basename "$timer")
        systemctl stop "$timer_name" 2>/dev/null || true
        systemctl disable "$timer_name" 2>/dev/null || true
        box_value "Timer" "$timer_name stopped and disabled" "YELLOW"
        ((disabled_count++))
    fi
done

if [ $disabled_count -eq 0 ]; then
    box_line "WARNING: No services or timers were found to disable"
else
    box_value "Total disabled" "$disabled_count units"
fi
box_end

box_begin "Cleanup"
box_value "Target directory" "$SYSTEMD_LIVE"

# Create backup directory (overwrites previous backups)
BACKUP_DIR="$SCRIPT_DIR/systemd_backup"
mkdir -p "$BACKUP_DIR"

backed_up_count=0
if [ -d "$SYSTEMD_STAGING" ]; then
    # Backup and remove service/timer files
    for file in "$SYSTEMD_LIVE"/sentrylab*.service "$SYSTEMD_LIVE"/sentrylab*.timer; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")
            cp "$file" "$BACKUP_DIR/" 2>/dev/null || true
            rm -f "$file"
            ((backed_up_count++))
        fi
    done
    
    if [ $backed_up_count -eq 0 ]; then
        box_line "WARNING: No systemd unit files found to backup"
    else
        box_value "Files backed up" "$backed_up_count units"
        box_value "Backup location" "$BACKUP_DIR"
        box_line "INFO: Systemd units removed from live directory" "GREEN"
    fi
else
    box_line "WARNING: Staging directory $SYSTEMD_STAGING does not exist"
fi

box_line "Reloading systemd daemon..."
systemctl daemon-reload
box_line "INFO: Daemon reloaded" "GREEN"

if [ $disabled_count -eq 0 ] && [ $backed_up_count -eq 0 ]; then
    box_line "WARNING: No changes made (0 units disabled, 0 files backed up)" "YELLOW"
    box_line "SentryLab services were not active or already removed"
else
    box_line "SentryLab services deactivated successfully" "GREEN"
    if [ $backed_up_count -gt 0 ]; then
        box_line "Customized units preserved in: $BACKUP_DIR" "CYAN"
    fi
fi
box_line "To activate again: $SCRIPT_DIR/start.sh" "CYAN"

box_end
