#!/bin/bash

#
# @file /usr/local/bin/sentrylab/wear.sh
# @author CmPi <cmpi@webe.fr>
# @brief Collects NVMe wear levels and publishes to MQTT
# @date 2025-12-29
# @version 1.0.362.5
# @usage Run periodically (e.g., every hour via cron or systemd timer)
# @notes * make it executable as usual
#          chmod +x /usr/local/bin/sentrylab/wear.sh
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

box_begin "NVMe Wear Collection"

if [[ "${PUSH_NVME_WEAR:-false}" == "true" ]]; then

    box_line "INFO: NVMe wear metrics publishing is enabled (PUSH_NVME_WEAR == true)"    

    # --- Initialisation JSON ---
    JSON=$(jq -n '{}')

    # --- Gather NVMe Wear Levels ---
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
            box_line "WARNING: Could not retrieve serial number for $nvme_dev"
            continue
        fi
        
        SN_LOWER=$(echo "$SN" | tr '[:upper:]' '[:lower:]')
        
        # Construire le chemin du device
        DEV="/dev/${nvme_dev}n1"
        
        if [[ ! -e "$DEV" ]]; then
            box_line "ERROR: Device not found: $DEV"
            continue
        fi
        
        box_line "Reading wear level for $nvme_dev (S/N: $SN)"
        
        # Lire le niveau d'usure avec smartctl
        # WARNING: This command WAKES the drive if sleeping
        WEAR=$(smartctl -A "$DEV" 2>/dev/null | grep -i "Percentage Used:" | cut -d: -f2 | xargs | tr -d '%')
        
        if [[ -z "$WEAR" ]]; then
            log_debug "  Could not read wear level for $nvme_dev, skipping"
            continue
        fi
        
        # Ajouter au JSON
        JSON=$(jq --arg k "nvme_${SN_LOWER}" --argjson v "$WEAR" '. + {($k): $v}' <<<"$JSON")
        log_debug "  NVMe $SN_LOWER wear: $WEAR%"
    done    


    # --- Publish JSON to MQTT ---
    if [[ "$DEBUG" != "true" ]]; then
        mqtt_publish_retain "$WEAR_TOPIC" "$JSON"
    else
        log_debug "DEBUG mode: MQTT publish skipped"
    fi

    # --- Test mode when run directly ---
    if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
        [[ "$DEBUG" == "true" ]] && echo "--- NAS WEAR TEST ---"
        [[ "$DEBUG" == "true" ]] && echo "$JSON" | jq .
        [[ "$DEBUG" == "true" ]] && echo "--- END OF TEST ---"
    fi

else
    box_line "INFO: NVMe wear metrics publishing is disabled (PUSH_NVME_WEAR != true)"    
fi    

box_end