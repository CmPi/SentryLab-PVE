#!/bin/bash

#
# @file /usr/local/bin/sentrylab/health.sh
# @author CmPi <cmpi@webe.fr>
# @brief Collects NVMe health status and publishes to MQTT
# @date 2025-12-29
# @version 1.0.363
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

box_begin "NVMe Health Collection"

if [[ "${PUSH_NVME_HEALTH:-false}" == "true" ]]; then

    box_line "INFO: NVMe health metrics publishing is enabled (PUSH_NVME_HEALTH == true)"    

    # --- Initialisation JSON ---
    JSON=$(jq -n '{}')

    # --- Gather NVMe Health Status ---
    for hw_path in /sys/class/hwmon/hwmon*; do
        hw_name=$(cat "$hw_path/name" 2>/dev/null || echo "")

        # Skip non-NVMe hwmon
        [[ "$hw_name" == "nvme" ]] || continue
        
        # Trouver le device NVMe correspondant
        nvme_link=$(readlink -f "$hw_path")
        nvme_dev=$(echo "$nvme_link" | grep -oP 'nvme\d+' | head -n1)
        
        if [[ -z "$nvme_dev" ]]; then
            box_line "ERROR: Could not determine nvme device for $(basename $hw_path)"
            continue
        fi
        
        # Récupérer le numéro de série depuis sysfs (sans réveiller)
        SN=$(cat "/sys/class/nvme/$nvme_dev/serial" 2>/dev/null | tr -d ' ')
        
        if [[ -z "$SN" ]]; then
            box_line "ERROR: Could not retrieve serial number for $nvme_dev"
            continue
        fi
        
        SN_LOWER=$(echo "$SN" | tr '[:upper:]' '[:lower:]')
        
        # Construire le chemin du device
        DEV="/dev/${nvme_dev}n1"
        
        if [[ ! -e "$DEV" ]]; then
            log_debug "Device not found: $DEV"
            continue
        fi
        
        box_line "Reading health status for $nvme_dev (S/N: $SN)"
        
        # Read health status with smartctl
        # WARNING: This command WAKES the drive if sleeping
        ST=$(smartctl -H "$DEV" 2>/dev/null | grep -i "test result" | cut -d: -f2 | xargs)
        
        if [[ -z "$ST" ]]; then
            log_debug "  Could not read health status for $nvme_dev, skipping"
            continue
        fi
        
        # Convertir en valeur binaire (0 = PASSED = OK = NO PROBLEM, 1 = FAILED = Problem)
        VAL=$([[ "$ST" == "PASSED" ]] && echo 0 || echo 1)
        
        # Ajouter au JSON
        JSON=$(jq --arg k "nvme_${SN_LOWER}" --argjson v "$VAL" '. + {($k): $v}' <<<"$JSON")
        
        if [[ "$VAL" == "1" ]]; then
            box_line "  NVMe $SN_LOWER health: OK (PASSED)"
        else
            box_line "  NVMe $SN_LOWER health: PROBLEM ($ST)"
        fi
    done

    # Collected in nightly active cycle; retain for availability
    mqtt_publish_retain "$HEALTH_TOPIC" "$JSON"

    box_end

    # --- Test mode when run directly ---
    if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
        [[ "$DEBUG" == "true" ]] && echo "--- NAS HEALTH TEST ---"
        [[ "$DEBUG" == "true" ]] && echo "$JSON" | jq .
        [[ "$DEBUG" == "true" ]] && echo "--- END OF TEST ---"
    fi
            











else
    box_line "INFO: System metrics publishing is disabled (PUSH_SYSTEM != true), exiting"
    box_end
    exit 0
fi

