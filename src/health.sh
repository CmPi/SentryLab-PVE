#!/bin/bash
#
# @file /usr/local/bin/sentrylab/health.sh
# @author CmPi <cmpi@webe.fr>
# @brief Collects NVMe health status and publishes to MQTT
# @date 2025-12-26
# @version 1.0.362.4
# @usage Run periodically (e.g., every hour via cron or systemd timer)
# @notes make it executable as usual
#        chmod +x /usr/local/bin/*.sh
#        WARNING: This script uses smartctl which WAKES sleeping drives
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

log_debug "--- NAS HEALTH SCAN STARTING ---"

# --- Gather NVMe Health Status ---
for hw_path in /sys/class/hwmon/hwmon*; do
    hw_name=$(cat "$hw_path/name" 2>/dev/null || echo "")

    # Skip non-NVMe hwmon
    [[ "$hw_name" == "nvme" ]] || continue
    
    # Trouver le device NVMe correspondant
    nvme_link=$(readlink -f "$hw_path")
    nvme_dev=$(echo "$nvme_link" | grep -oP 'nvme\d+' | head -n1)
    
    if [[ -z "$nvme_dev" ]]; then
        log_debug "Could not determine nvme device for $(basename $hw_path)"
        continue
    fi
    
    # Récupérer le numéro de série depuis sysfs (sans réveiller)
    SN=$(cat "/sys/class/nvme/$nvme_dev/serial" 2>/dev/null | tr -d ' ')
    
    if [[ -z "$SN" ]]; then
        log_debug "Could not retrieve serial number for $nvme_dev"
        continue
    fi
    
    SN_LOWER=$(echo "$SN" | tr '[:upper:]' '[:lower:]')
    
    # Construire le chemin du device
    DEV="/dev/${nvme_dev}n1"
    
    if [[ ! -e "$DEV" ]]; then
        log_debug "Device not found: $DEV"
        continue
    fi
    
    log_debug "Reading health status for $nvme_dev (S/N: $SN)"
    
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
        log_debug "  NVMe $SN_LOWER health: OK (PASSED)"
    else
        log_debug "  NVMe $SN_LOWER health: PROBLEM ($ST)"
    fi
done

mqtt_publish "$HEALTH_TOPIC" "$JSON"

log_debug "--- NAS HEALTH SCAN COMPLETE ---"

# --- Test mode when run directly ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    [[ "$DEBUG" == "true" ]] && echo "--- NAS HEALTH TEST ---"
    [[ "$DEBUG" == "true" ]] && echo "$JSON" | jq .
    [[ "$DEBUG" == "true" ]] && echo "--- END OF TEST ---"
fi
        