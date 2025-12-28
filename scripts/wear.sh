#!/bin/bash
#
# @file /usr/local/bin/sentrylab/wear.sh
# @author CmPi <cmpi@webe.fr>
# @brief Relève le niveau d'usure des NVMe et les publie via MQTT
# @date 2025-12-26
# @version 1.0.359.5
# @usage À exécuter périodiquement (ex: toutes les heures via cron ou timer systemd)
# @notes make it executable as usual
#        chmod +x /usr/local/bin/*.sh
#        ATTENTION: Ce script utilise smartctl qui RÉVEILLE les disques en veille
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

log_debug "--- NAS WEAR SCAN STARTING ---"

# --- Gather NVMe Wear Levels ---
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
    
    log_debug "Reading wear level for $nvme_dev (S/N: $SN)"
    
    # Lire le niveau d'usure avec smartctl
    # ATTENTION: Cette commande RÉVEILLE le disque s'il est en veille
    WEAR=$(smartctl -A "$DEV" 2>/dev/null | grep -i "Percentage Used:" | awk -F: '{print $2}' | xargs | tr -d '%')
    
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
    mqtt_publish "$WEAR_TOPIC" "$JSON"
else
    log_debug "DEBUG mode: MQTT publish skipped"
fi


log_debug "--- NAS WEAR SCAN COMPLETE ---"

# --- Test mode si lancé directement ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    [[ "$DEBUG" == "true" ]] && echo "--- NAS WEAR TEST ---"
    [[ "$DEBUG" == "true" ]] && echo "$JSON" | jq .
    [[ "$DEBUG" == "true" ]] && echo "--- END OF TEST ---"
fi
