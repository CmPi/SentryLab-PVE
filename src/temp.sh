#!/bin/bash

#
# @file /usr/local/bin/sentrylab/temp.sh
# @author CmPi <cmpi@webe.fr>
# @brief Releve les températures CPU, NVMe et NAS ambient et les publie via MQTT
# @date 2025-12-27
# @version 1.1.361
# @usage À exécuter périodiquement (ex: via cron ou timer systemd)
# @notes * make it executable as usual using the command:
#          chmod +x /usr/local/bin/*.sh
#        * set DEBUG to true in config.conf and run it in simulation mode
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

# --- Initialisation JSON ---
JSON=$(jq -n '{}')

box_begin "NVMe Temperature Collection"

if [[ "$PUSH_SYSTEM" == "true" ]]; then
    box_line "INFO: System metrics publishing is enabled (PUSH_SYSTEM == true)"    

    # --- 3. NVMe Temperatures ---
    for hw_path in /sys/class/hwmon/hwmon*; do
        hw_name=$(cat "$hw_path/name" 2>/dev/null || echo "")
        [[ "$hw_name" == "nvme" ]] || continue
        hw_num=$(basename "$hw_path")
        nvme_link=$(readlink -f "$hw_path")
        nvme_dev=$(echo "$nvme_link" | grep -oP 'nvme\d+' | head -n1)
        if [[ -z "$nvme_dev" ]]; then
            log_debug "Could not determine nvme device for $hw_num"
            continue
        fi
        SN=$(cat "/sys/class/nvme/$nvme_dev/serial" 2>/dev/null | tr -d ' ')
        if [[ -z "$SN" ]]; then
            box_line "ERROR; Could not retrieve serial number for $nvme_dev"
            continue
        fi
        SN_LOWER=$(echo "$SN" | tr '[:upper:]' '[:lower:]')
        box_value "$hw_num" "$nvme_dev (S/N: $SN)"
        
        temp_count=0
        for t_file in "$hw_path"/temp*_input; do
            [[ -f "$t_file" ]] || continue
            temp_num=$(basename "$t_file" | sed 's/temp\([0-9]*\)_input/\1/')
            raw_val=$(cat "$t_file" 2>/dev/null || echo "0")
            temp_val=$(awk "BEGIN{printf \"%.1f\", $raw_val/1000}")
            label_file="${t_file%_input}_label"
            if [[ -f "$label_file" ]]; then
                label=$(cat "$label_file" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')
            else
                case $temp_num in
                    1) label="composite" ;;
                    2) label="sensor1" ;;
                    3) label="sensor2" ;;
                    *) label="sensor$temp_num" ;;
                esac
            fi
            key="nvme_${SN_LOWER}_${label}"
            JSON=$(jq --arg k "$key" --arg v "$temp_val" '. + {($k): ($v | tonumber)}' <<<"$JSON")
            log_debug "  $nvme_dev $label (temp$temp_num): $temp_val°C"
            temp_count=$((temp_count + 1))
        done
        log_debug "  Found $temp_count temperature sensor(s) for $nvme_dev"
    done

    # --- Publish JSON to MQTT (No-Retain) ---
    mqtt_publish_no_retain "$TEMP_TOPIC" "$JSON"

else
    box_line "INFO: System metrics publishing is disabled (PUSH_SYSTEM != true)"    
fi

box_end
