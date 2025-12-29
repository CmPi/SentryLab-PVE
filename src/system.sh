#!/bin/bash

#
# @file /usr/local/bin/sentrylab/temp.sh
# @author CmPi <cmpi@webe.fr>
# @brief Releve les températures CPU, NVMe et NAS ambient et les publie via MQTT
# @date 2025-12-27
# @version 1.0.362
# @usage À exécuter périodiquement (ex: via cron ou timer systemd)
# @notes * make it executable as usual using the command:
#          chmod +x /usr/local/bin/*.sh
#        * set DEBUG to true in config.conf and run it in simulation mode
#        * box_begin, box_line, box_value and box_end functions do nothing when DEBUG is false 

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
JSON_TEMP=$(jq -n '{}')
JSON_SYSTEM=$(jq -n '{}')

box_begin "System metrics collection"

if [[ "$PUSH_SYSTEM" == "true" ]]; then
    box_line "INFO: System metrics publishing is enabled (PUSH_SYSTEM == true)"    

    # --- 1. CPU Temperature ---
    CPU_TEMP=$(sensors -j | jq -r '."coretemp-isa-0000"?["Package id 0"]?["temp1_input"] // empty')
    if [[ -n "$CPU_TEMP" ]]; then
        JSON_TEMP=$(jq --argjson v "$CPU_TEMP" '. + {cpu: $v}' <<<"$JSON_TEMP")
        box_value "cpu temperature" "$CPU_TEMP°C"
    else
        box_line "WARNING: CPU temperature could not be retrieved"
    fi

    # --- 2. NAS Ambient Temperature ---
    ACPI_HWMON=$(grep -l "acpitz" /sys/class/hwmon/hwmon*/name 2>/dev/null | head -n1 | cut -d/ -f5)
    if [[ -n "$ACPI_HWMON" ]]; then
        RAW_AMB=$(cat "/sys/class/hwmon/$ACPI_HWMON/temp1_input")
        NAS_AMB=$(awk "BEGIN{printf \"%.1f\", $RAW_AMB/1000}")
        JSON_TEMP=$(jq --argjson v "$NAS_AMB" '. + {chassis: $v}' <<<"$JSON_TEMP")
        box_value "chassis temperature" "$NAS_AMB°C"
    else
        box_line "WARNING: NAS ambient temperature could not be retrieved"
    fi

    # --- CPU Cores (Static) ---
    if command -v nproc >/dev/null; then
        CPU_CORES=$(nproc)
        JSON_SYSTEM=$(jq --argjson v "$CPU_CORES" '. + {cpu_cores: $v}' <<<"$JSON_SYSTEM")
        box_value "cpu cores" "$CPU_CORES"
    else
        box_line "WARNING: Could not determine number of CPU cores"
    fi

    # --- CPU Load Average (5 min) ---
    if [[ -f /proc/loadavg ]]; then
        CPU_LOAD=$(awk '{print $2}' /proc/loadavg)
        JSON_SYSTEM=$(jq --argjson v "$CPU_LOAD" '. + {cpu_load_5m: $v}' <<<"$JSON_SYSTEM")
        box_value "cpu load average (5 min)" "$CPU_LOAD"
    else
        box_line "WARNING: Could not retrieve CPU load average"
    fi

    # --- Publish JSONs to respective topics to MQTT (No-Retain) ---
    box_line ""
    box_line "Published system metrics to MQTT topics" "$BOX_WIDTH" "MAGENTA"
    mqtt_publish_no_retain "$TEMP_TOPIC" "$JSON_TEMP"
    mqtt_publish_no_retain "$SYSTEM_TOPIC" "$JSON_SYSTEM"

else
    box_line "SKIPPED: System metrics publishing is disabled (PUSH_SYSTEM != true)"    
fi

box_end
