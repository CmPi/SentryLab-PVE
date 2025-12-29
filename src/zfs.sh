#!/bin/bash

#
# @file /usr/local/bin/sentrylab/zfs.sh
# @author CmPi <cmpi@webe.fr>
# @brief Collects ZFS pool health and metrics and publishes to MQTT
# @date 2025-12-29
# @version 1.0.363
# @usage Run periodically (e.g., every 5 minutes via cron or systemd timer)
# @notes * make it executable as usual using the command:
#          chmod +x /usr/local/bin/sentrylab/zfs.sh
#        * set DEBUG to true in config.conf and run it in simulation mode
#        * This script does NOT wake sleeping drives
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

box_begin "ZFS Pools Metrics Collection"

if [[ "${PUSH_ZFS:-false}" == "true" ]]; then

    # --- Initialisation JSON ---
    JSON=$(jq -n '{}')

    # --- Liste tous les pools ZFS ---
    POOLS=$(zpool list -H -o name 2>/dev/null || true)

    if [[ -z "$POOLS" ]]; then
        box_line "WARNING: No ZFS pools found"
        box_end
        exit 0
    fi

    # --- Pour chaque pool ---
    while IFS= read -r pool; do
        [[ -z "$pool" ]] && continue
        
        box_line "Processing pool: $pool"
        
        # --- Health Status ---
        HEALTH=$(zpool list -H -o health "$pool" 2>/dev/null || echo "UNKNOWN")
        HEALTH_VAL=$([[ "$HEALTH" == "ONLINE" ]] && echo 1 || echo 0)
        
        # --- Capacity ---
        SIZE=$(zpool list -H -o size -p "$pool" 2>/dev/null || echo "0")
        ALLOC=$(zpool list -H -o allocated -p "$pool" 2>/dev/null || echo "0")
        FREE=$(zpool list -H -o free -p "$pool" 2>/dev/null || echo "0")

        # Skip sleeping pools in passive mode (best-effort based on member devices)
        if [[ "$MONITOR_MODE" == "passive" ]]; then
            POOL_DEVS=$(zpool status -P "$pool" 2>/dev/null | awk '/^\s*\/dev\//{print $1}' | sort -u)
            if [[ -n "$POOL_DEVS" ]]; then
                asleep=false
                while IFS= read -r dev; do
                    [[ -z "$dev" ]] && continue
                    if ! device_is_awake "$dev"; then
                        asleep=true
                        break
                    fi
                done <<< "$POOL_DEVS"
                if [[ "$asleep" == true ]]; then
                    box_line "SKIP: Pool $pool skipped (device sleeping, passive mode)"
                    continue
                fi
            fi
        fi
        
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
        box_line "Pool: $pool" "MAGENTA"
        box_value "Health" "$HEALTH (status: $HEALTH_VAL)"
        box_value "Usage" "Usage: $USAGE% ($ALLOC / $SIZE bytes)"
        box_value "Fragmentation" "$FRAG%"
        
    done <<< "$POOLS"

    # --- Publish JSON to MQTT (Retain pour la persistance de l'état de santé) ---
    mqtt_publish_retain "$ZFS_TOPIC" "$JSON"

    # --- Test mode when run directly ---
    if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
        [[ "${DEBUG:-false}" == "true" ]] && echo "$JSON" | jq .
    fi

else
    box_line "INFO: ZFS metrics publishing is disabled (PUSH_ZFS != true)"
fi

box_end

exit 0