#!/bin/bash

#
# @file /usr/local/bin/sentrylab/zfs.sh
# @author CmPi <cmpi@webe.fr>
# @brief Collects ZFS pool health and metrics and publishes to MQTT
# @date 2025-12-27
# @version 1.0.362.4
# @usage Run periodically (e.g., every 5 minutes via cron or systemd timer)
# @notes * make it executable as usual using the command:
#          chmod +x /usr/local/bin/sentrylab/zfs.sh
#        * This script does NOT wake sleeping drives
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

log_debug "--- NAS ZFS SCAN STARTING ---"

# --- Liste tous les pools ZFS ---
POOLS=$(zpool list -H -o name 2>/dev/null || true)

if [[ -z "$POOLS" ]]; then
    log_debug "No ZFS pools found"
    exit 0
fi

# --- Pour chaque pool ---
while IFS= read -r pool; do
    [[ -z "$pool" ]] && continue
    
    log_debug "Processing pool: $pool"
    
    # --- Health Status ---
    HEALTH=$(zpool list -H -o health "$pool" 2>/dev/null || echo "UNKNOWN")
    HEALTH_VAL=$([[ "$HEALTH" == "ONLINE" ]] && echo 1 || echo 0)
    
    # --- Capacity ---
    SIZE=$(zpool list -H -o size -p "$pool" 2>/dev/null || echo "0")
    ALLOC=$(zpool list -H -o allocated -p "$pool" 2>/dev/null || echo "0")
    FREE=$(zpool list -H -o free -p "$pool" 2>/dev/null || echo "0")
    
    # Calculer le pourcentage d'utilisation
    if [[ "$SIZE" -gt 0 ]]; then
        USAGE=$(printf "%.1f" "$(echo "scale=1; ($ALLOC / $SIZE) * 100" | bc)")
    else
        USAGE="0.0"
    fi
    
    # --- Fragmentation ---
    FRAG=$(zpool list -H -o frag "$pool" 2>/dev/null | tr -d '%' || echo "0")
    
    # --- Normaliser le nom du pool pour JSON (remplacer - par _) ---
    POOL_NORM=$(echo "$pool" | tr '-' '_' | tr '[:upper:]' '[:lower:]')
    
    # --- Ajouter au JSON ---
    JSON=$(jq \
        --arg pool "$POOL_NORM" \
        --arg health "$HEALTH" \
        --argjson health_val "$HEALTH_VAL" \
        --arg size "$SIZE" \
        --arg alloc "$ALLOC" \
        --arg free "$FREE" \
        --arg usage "$USAGE" \
        --arg frag "$FRAG" \
        '. + {
            ($pool + "_health"): $health,
            ($pool + "_health_status"): $health_val,
            ($pool + "_size_bytes"): ($size | tonumber),
            ($pool + "_allocated_bytes"): ($alloc | tonumber),
            ($pool + "_free_bytes"): ($free | tonumber),
            ($pool + "_usage_percent"): ($usage | tonumber),
            ($pool + "_fragmentation_percent"): ($frag | tonumber)
        }' <<<"$JSON")
    
    log_debug "  Pool: $pool"
    log_debug "    Health: $HEALTH (status: $HEALTH_VAL)"
    log_debug "    Usage: $USAGE% ($ALLOC / $SIZE bytes)"
    log_debug "    Fragmentation: $FRAG%"
    
done <<< "$POOLS"

# --- Publish JSON to MQTT (Retain pour la persistance de l'état de santé) ---
mqtt_publish_retain "$ZFS_TOPIC" "$JSON"

log_debug "--- NAS ZFS SCAN COMPLETE ---"

# --- Test mode when run directly ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    [[ "${DEBUG:-false}" == "true" ]] && echo "$JSON" | jq .
fi