#!/bin/bash

#
# @file /usr/local/bin/sentrylab/discovery.sh
# @author CmPi <cmpi@webe.fr>
# @brief Publie les capteurs du NAS vers Home Assistant pour la découverte automatique
# @date 2025-12-27
# @version 1.1.361
# @usage à lancer au boot pour déclarer les capteurs Home Assistant
# @notes * make it executable as usual using the command:
#          chmod +x /usr/local/bin/*.sh
#        * set DEBUG to true in config.conf and run it in simulation mode to see the generated payloads (not published to MQTT)
#

set -euo pipefail

# --- Include configuration et fonctions utilitaires ---
# On cherche d'abord dans le dossier local du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/utils.sh" ]; then
    source "$SCRIPT_DIR/utils.sh"
else
    echo "ERROR: utils.sh not found!" >&2
    exit 1
fi

# --- Attente du Broker MQTT ---
MAX_RETRIES=20
RETRY_COUNT=0

log_debug "Checking MQTT Broker availability ($BROKER:$PORT)..."

while ! nc -z "$BROKER" "$PORT"; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        log_error "Broker unreachable after $MAX_RETRIES attempts. Exiting."
        exit 1
    fi
    log_debug "Broker not ready... retrying in 10s ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 10
done
log_debug "Broker is UP! Proceeding with discovery."

# --- Enable nullglob for NVMe temperature sensors et pools enumeration ---
shopt -s nullglob

# --- Device JSON pour Home Assistant ---
DEVICE_JSON="{\"identifiers\": [\"$HOST_NAME\"], \"name\": \"$HOST_NAME\", \"model\": \"Node\", \"manufacturer\": \"Proxmox\"}"

log_debug "--- STARTING DISCOVERY ---"

# --- 1. Register CPU sensor ---
HA_ID="${HOST_NAME}_cpu_temp"
HA_LABEL="Température du CPU"
CFG_TOPIC="${HA_DISCOVERY_PREFIX}/sensor/${HA_ID}/config"
PAYLOAD=$(jq -n \
    --arg name "$HA_LABEL" \
    --arg unique_id "$HA_ID" \
    --arg stat_t "$TEMP_TOPIC" \
    --arg val_tpl '{{ value_json.cpu }}' \
    --arg unit "°C" \
    --arg icon "mdi:thermometer" \
    --arg dev_cla "temperature" \
    --arg availability "$AVAIL_TOPIC" \
    --argjson dev "$DEVICE_JSON" \
    '{
        name: $name,
        unique_id: $unique_id,
        object_id: $unique_id,
        state_topic: $stat_t,
        value_template: $val_tpl,
        unit_of_measurement: $unit,
        icon: $icon,
        device_class: $dev_cla,
        availability_topic: $availability,        
        dev: $dev
    }'
)
mqtt_publish_retain "$CFG_TOPIC" "$PAYLOAD"

# --- 2. Register Chassis temperature sensor ---
HA_ID="${HOST_NAME}_chassis_temp"
HA_LABEL="Température du chassis"
CFG_TOPIC="${HA_DISCOVERY_PREFIX}/sensor/${HA_ID}/config"
PAYLOAD=$(jq -n \
    --arg name "$HA_LABEL" \
    --arg unique_id "$HA_ID" \
    --arg stat_t "$TEMP_TOPIC" \
    --arg val_tpl '{{ value_json.chassis }}' \
    --arg unit "°C" \
    --arg icon "mdi:thermometer" \
    --arg dev_cla "temperature" \
    --arg av_t "$AVAIL_TOPIC" \
    --argjson dev "$DEVICE_JSON" \
    '{
        name: $name,
        unique_id: $unique_id,
        object_id: $unique_id,
        state_topic: $stat_t,
        value_template: $val_tpl,
        unit_of_measurement: $unit,
        icon: $icon,
        device_class: $dev_cla,
        availability_topic: $av_t,        
        dev: $dev
    }'
)
mqtt_publish_retain "$CFG_TOPIC" "$PAYLOAD"

# --- 3. Register NVMe sensors ---
for hw_path in /sys/class/hwmon/hwmon*; do
    hw_name=$(cat "$hw_path/name" 2>/dev/null || echo "")
    [[ "$hw_name" == "nvme" ]] || continue

    nvme_link=$(readlink -f "$hw_path")
    nvme_dev=$(echo "$nvme_link" | grep -oP 'nvme\d+' | head -n1)
    
    NVME_SLOT_ID="Slot $(( $(echo "$nvme_dev" | grep -oP '\d+') + 1 ))"
    SN=$(cat "/sys/class/nvme/$nvme_dev/serial" 2>/dev/null | tr -d ' ')
    [[ -n "$SN" ]] || continue
    SN_LOWER=$(echo "$SN" | tr '[:upper:]' '[:lower:]')
    
    # Wear sensor
    HA_ID="nvme_${SN_LOWER}_wear"
    CFG_TOPIC="${HA_DISCOVERY_PREFIX}/sensor/${HA_ID}/config"
    PAYLOAD=$(jq -n --arg name "Usure SSD ${SN}" --arg unique_id "$HA_ID" --arg stat_t "$WEAR_TOPIC" --arg val_tpl "{{ value_json.nvme_${SN_LOWER} }}" --arg av_t "$AVAIL_TOPIC" --argjson dev "$DEVICE_JSON" \
        '{name: $name, unique_id: $unique_id, object_id: $unique_id, state_topic: $stat_t, value_template: $val_tpl, unit_of_measurement: "%", icon: "mdi:gauge", availability_topic: $av_t, dev: $dev}')
    mqtt_publish_retain "$CFG_TOPIC" "$PAYLOAD"

    # Health binary sensor
    HA_ID="nvme_${SN_LOWER}_health"
    CFG_TOPIC="${HA_DISCOVERY_PREFIX}/binary_sensor/${HA_ID}/config"
    PAYLOAD=$(jq -n --arg name "Santé SSD ${SN}" --arg unique_id "$HA_ID" --arg stat_t "$HEALTH_TOPIC" --arg val_tpl "{{ value_json.nvme_${SN_LOWER} }}" --arg av_t "$AVAIL_TOPIC" --argjson dev "$DEVICE_JSON" \
        '{name: $name, unique_id: $unique_id, object_id: $unique_id, state_topic: $stat_t, value_template: $val_tpl, payload_on: "1", payload_off: "0", device_class: "problem", availability_topic: $av_t, icon: "mdi:heart-pulse", dev: $dev}')
    mqtt_publish_retain "$CFG_TOPIC" "$PAYLOAD"
done

# --- 4. ZFS pools discovery ---
POOLS=$(zpool list -H -o name 2>/dev/null || true)
for pool in $POOLS; do
    POOL_NORM=$(echo "$pool" | tr '-' '_' | tr '[:upper:]' '[:lower:]')
    
    # Status Sensor
    HA_ID="${HOST_NAME}_zfs_${POOL_NORM}_status"
    CFG_TOPIC="${HA_DISCOVERY_PREFIX}/sensor/${HA_ID}/config"
    PAYLOAD=$(jq -n --arg name "Statut pool ${pool}" --arg unique_id "$HA_ID" --arg stat_t "$ZFS_TOPIC" --arg val_tpl "{{ value_json.${POOL_NORM}_health }}" --arg av_t "$AVAIL_TOPIC" --argjson dev "$DEVICE_JSON" \
        '{name: $name, unique_id: $unique_id, object_id: $unique_id, state_topic: $stat_t, value_template: $val_tpl, availability_topic: $av_t, icon: "mdi:database", dev: $dev}')
    mqtt_publish_retain "$CFG_TOPIC" "$PAYLOAD"
    
    # Usage Sensor
    HA_ID="${HOST_NAME}_zfs_${POOL_NORM}_usage"
    CFG_TOPIC="${HA_DISCOVERY_PREFIX}/sensor/${HA_ID}/config"
    PAYLOAD=$(jq -n --arg name "Utilisation pool ${pool}" --arg unique_id "$HA_ID" --arg stat_t "$ZFS_TOPIC" --arg val_tpl "{{ value_json.${POOL_NORM}_usage_percent }}" --arg av_t "$AVAIL_TOPIC" --argjson dev "$DEVICE_JSON" \
        '{name: $name, unique_id: $unique_id, object_id: $unique_id, state_topic: $stat_t, value_template: $val_tpl, unit_of_measurement: "%", icon: "mdi:chart-donut", availability_topic: $av_t, dev: $dev}')
    mqtt_publish_retain "$CFG_TOPIC" "$PAYLOAD"
done

# On confirme la disponibilité du NAS
mqtt_publish_retain "$AVAIL_TOPIC" "online"

log_debug "--- DISCOVERY COMPLETE ---"