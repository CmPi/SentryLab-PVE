#!/bin/bash

#
# @file /usr/local/bin/sentrylab/non-zfs.sh
# @author CmPi <cmpi@webe.fr>
# @brief Collects status of non-pool drives
# @date 2025-12-29
# @version 1.0.359.7
# @usage Run periodically (e.g., every hour via cron or systemd timer)
# @notes * make it executable as usual
#          chmod +x /usr/local/bin/*.sh
#        * set DEBUG to true in config.conf and run it in simulation mode
#        * WARNING: This script uses smartctl which WAKES sleeping drives
#        * box_begin, box_line, box_value and box_end functions do nothing when DEBUG is false
#

set -euo pipefail

# Load shared utility functions from the script directory.
# Abort execution if the required file is missing.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/utils.sh" ]; then
    source "$SCRIPT_DIR/utils.sh"
else
    echo "ERROR: Required file '$SCRIPT_DIR/utils.sh' not found." >&2
    exit 1
fi

# Monitoring mode: active (default) or passive
MONITOR_MODE="${MONITOR_MODE:-${1:-active}}"
MONITOR_MODE=${MONITOR_MODE,,}

box_begin "Non-ZFS Drives metrics Collection"

if [[ "${PUSH_NON_ZFS:-false}" == "true" ]]; then

    box_line "INFO: Non-ZFS drives metrics publishing is enabled (PUSH_NON_ZFS == true)"

    JSON_DISKS="{}"
    FOUND_DISKS=0

    while read -r source target fstype size_bytes free_bytes; do
        DISK_ID=$(echo "$target" | tr '/' '_' | sed 's/^_//;s/^$/root/')

        case "$fstype" in
            efivarfs|proc|sysfs|devpts|cgroup*|debugfs|tracefs|configfs|squashfs|overlay)
                box_line "SKIP: non-pertinent fstype $fstype for $target"
                continue
                ;;
        esac

        if [[ "$target" == /sys/* || "$target" == /proc/* || "$target" == /dev/* || "$target" == /run/* ]]; then
            box_line "SKIP: mountpoint $target appears system-managed"
            continue
        fi

        # Skip sleeping devices in passive mode (best-effort)
        if [[ "$MONITOR_MODE" == "passive" && "$source" == /dev/* ]]; then
            if ! device_is_awake "$source"; then
                box_line "SKIP: $target on $source sleeping (passive mode)"
                continue
            fi
        fi

        JSON_DISKS=$(jq --argjson v "$free_bytes" '. + {"'"${DISK_ID}"'_free_bytes": $v}' <<<"$JSON_DISKS")
        JSON_DISKS=$(jq --argjson v "$size_bytes" '. + {"'"${DISK_ID}"'_size_bytes": $v}' <<<"$JSON_DISKS")

        box_value "Captured" "$target" 80
        FOUND_DISKS=$((FOUND_DISKS + 1))

    done < <(df -B1 -x tmpfs -x devtmpfs -x zfs --output=source,target,fstype,size,avail | tail -n +2)

    if [[ $FOUND_DISKS -eq 0 ]]; then
        box_line "INFO: No eligible non-ZFS mountpoints found"
    else
        mqtt_publish_retain "$DISK_TOPIC" "$JSON_DISKS"
        box_line "Published non-ZFS disk metrics to MQTT (retained)" "MAGENTA"
    fi

else
    box_line "INFO: Non-ZFS drives metrics publishing is disabled (PUSH_NON_ZFS != true)" 
fi

box_end
