#!/bin/bash

#
# @file /usr/local/bin/sentrylab/discovery.sh
# @author CmPi <cmpi@webe.fr>
# @brief Publie les capteurs du NAS vers Home Assistant pour la découverte automatique
# @date 2025-12-28
# @version 1.1.361
# @usage à lancer au boot pour déclarer les capteurs Home Assistant
# @notes * make it executable as usual using the command:
#          chmod +x /usr/local/bin/*.sh
#        * set DEBUG to true in config.conf and run it in simulation mode to see the generated payloads (not published to MQTT)
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

# --- Attente du Broker MQTT ---
MAX_RETRIES=40
RETRY_COUNT=0

log_debug "Checking MQTT Broker availability ($BROKER:$PORT)..."

# nc (netcat) vérifie si le port est ouvert sans envoyer de données
while ! nc -z "$BROKER" "$PORT"; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        log_error "Broker unreachable after $MAX_RETRIES attempts. Exiting."
        exit 1
    fi
    log_debug "Broker not ready... retrying in 10s ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 15
done
log_debug "Broker is UP! Proceeding with discovery."

# --- Enable nullglob for NVMe temperature sensors et pools enumaration ---
shopt -s nullglob

# --- Device JSON pour Home Assistant ---
DEVICE_JSON="{\"identifiers\": [\"$HOST_NAME\"], \"name\": \"$HOST_NAME\", \"model\": \"Node\", \"manufacturer\": \"Proxmox\"}"

log_debug "--- STARTING DISCOVERY ---"

# --- Initialisation du JSON pour la publication MQTT ---
JSON=$(jq -n '{}')

# --- CSVs for IA dashboard generation ---

CSV_LINES="HA_ID,Type,Label,Serial,Slot"$'\n'

CSV_POOLS_HDR=""
CSV_POOLS_DATA=""
CSV_POOLS_HDR_ADDED=false

# --- 1. Register CPU sensor ---

# include hostname in HA ID (to avoid conflicts if other NAS or Workstations report their CPU temperature)

HA_ID="${HOST_NAME}_cpu_temp"
HA_LABEL="Température du CPU"
CFG_TOPIC="homeassistant/sensor/${HA_ID}/config"
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
CSV_LINES+="${HOST_NAME}_${HA_ID},temperature,\"${HA_LABEL}\",unknown,N/A"$'\n'

# --- 2. Register Chassis temperature sensor ---

# include hostname in HA ID (to avoid conflicts if other NAS or Workstations report their CPU temperature)

HA_ID="${HOST_NAME}_chassis_temp"
HA_LABEL="Température du chassis"
CFG_TOPIC="homeassistant/sensor/${HA_ID}/config"
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
CSV_LINES+="${HOST_NAME}_${HA_ID},temperature,\"${HA_LABEL}\",unknown,N/A"$'\n'

# --- 3. Register NVMe sensors for Home Assistant discovery ---

# do not include hostname in HA ID (NVME S/N are unique)
# a NVME may eventually be moved to another machine, so we rely on S/N only

for hw_path in /sys/class/hwmon/hwmon*; do
    hw_name=$(cat "$hw_path/name" 2>/dev/null || echo "")
    [[ "$hw_name" == "nvme" ]] || continue

    hw_num=$(basename "$hw_path")
    nvme_link=$(readlink -f "$hw_path")
    nvme_dev=$(echo "$nvme_link" | grep -oP 'nvme\d+' | head -n1)
    
    # Calcul du Slot physique (nvme0 -> Slot 1)
    NVME_SLOT_ID="Slot $(( $(echo "$nvme_dev" | grep -oP '\d+') + 1 ))"
    [[ -n "$nvme_dev" ]] || { log_debug "Could not determine nvme device for $hw_num"; continue; }
    SN=$(cat "/sys/class/nvme/$nvme_dev/serial" 2>/dev/null | tr -d ' ')
    [[ -n "$SN" ]] || { log_debug "Could not retrieve serial number for $nvme_dev"; continue; }
    SN_LOWER=$(echo "$SN" | tr '[:upper:]' '[:lower:]')
    MODEL=$(cat "/sys/class/nvme/$nvme_dev/model" 2>/dev/null | tr -d ' ' || echo "NVMe")
    log_debug "Processing NVMe: $MODEL ($SN)"

    # --- Wear sensor ---
    HA_ID="nvme_${SN_LOWER}_wear"
    HA_LABEL="Usure du SSD ${SN}"
    CFG_TOPIC="homeassistant/sensor/${HA_ID}/config"      # pour temperature
    PAYLOAD=$(jq -n \
        --arg name "$HA_LABEL" \
        --arg unique_id "$HA_ID" \
        --arg stat_t "$WEAR_TOPIC" \
        --arg val_tpl "{{ value_json.nvme_${SN_LOWER} }}" \
        --arg av_t "$AVAIL_TOPIC" \
        --argjson dev "$DEVICE_JSON" \
        '{
            name: $name,
            unique_id: $unique_id,
            object_id: $unique_id,
            state_topic: $stat_t,
            value_template: $val_tpl,
            unit_of_measurement: "%",
            icon: "mdi:gauge",
            availability_topic: $av_t,        
            dev: $dev
        }'
    )
    mqtt_publish_retain "$CFG_TOPIC" "$PAYLOAD"
    CSV_LINES+="${HOST_NAME}_${HA_ID},Wear,\"${HA_LABEL}\",${SN},${NVME_SLOT_ID}"$'\n'

    # --- Health binary sensor ---
    HA_ID="nvme_${SN_LOWER}_health"
    HA_LABEL="Santé du SSD ${SN} (slot ${NVME_SLOT_ID})"
    CFG_TOPIC="homeassistant/binary_sensor/${HA_ID}/config" 
    PAYLOAD=$(jq -n \
        --arg name "$HA_LABEL" \
        --arg unique_id "$HA_ID" \
        --arg stat_t "$HEALTH_TOPIC" \
        --arg val_tpl "{{ value_json.nvme_${SN_LOWER} }}" \
        --arg av_t "$AVAIL_TOPIC" \
        --argjson dev "$DEVICE_JSON" \
        '{
            name: $name,
            unique_id: $unique_id,
            object_id: $unique_id,
            state_topic: $stat_t,
            value_template: $val_tpl,
            payload_on: "1",      
            payload_off: "0",
            device_class: "problem",
            availability_topic: $av_t,        
            icon: "mdi:heart-pulse",
            dev: $dev
        }'
    )
    mqtt_publish_retain "$CFG_TOPIC" "$PAYLOAD"
    CSV_LINES+="${HOST_NAME}_${HA_ID},Health,\"${HA_LABEL}\",${SN},${NVME_SLOT_ID}"$'\n'

    # --- Temperature sensors ---
    for t_file in "$hw_path"/temp*_input; do
        [[ -f "$t_file" ]] || continue
        temp_num=$(basename "$t_file" | sed 's/temp\([0-9]*\)_input/\1/')
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
        label_display=$(echo "$label" | sed 's/_/ /g' | sed 's/\b\(.\)/\u\1/g')
        HA_ID="nvme_${SN_LOWER}_${label}"
        HA_LABEL="Température ${label_display} du SSD ${SN}"
        CFG_TOPIC="homeassistant/sensor/${HA_ID}/config" 
        PAYLOAD=$(jq -n \
            --arg name "$HA_LABEL" \
            --arg unique_id "$HA_ID" \
            --arg stat_t "$TEMP_TOPIC" \
            --arg val_tpl "{{ value_json.nvme_${SN_LOWER}_${label} }}" \
            --arg av_t "$AVAIL_TOPIC" \
            --argjson dev "$DEVICE_JSON" \
            '{
                name: $name,
                unique_id: $unique_id,
                object_id: $unique_id,
                state_topic: $stat_t,
                value_template: $val_tpl,
                unit_of_measurement: "°C",
                device_class: "temperature",
                availability_topic: $av_t,        
                icon: "mdi:thermometer",
                dev: $dev
            }'
        )
        mqtt_publish_retain "$CFG_TOPIC" "$PAYLOAD"
        CSV_LINES+="${HOST_NAME}_${HA_ID},${label},\"${HA_LABEL}\",${SN},${NVME_SLOT_ID}"$'\n'
        log_debug "  Registered NVMe temperature sensor: $label"
    done
done

# --- ZFS pools discovery ---
POOLS=$(zpool list -H -o name 2>/dev/null || true)

log_debug "-- Pools ZFS ${POOLS}"

for pool in $POOLS; do
    POOL_NORM=$(echo "$pool" | tr '-' '_' | tr '[:upper:]' '[:lower:]')

    log_debug "Registering ZFS pools: $pool"

    # --- Health (sensor) ---
    HA_ID="${HOST_NAME}_zfs_${POOL_NORM}_status"
    HA_LABEL="Statut du pool ${pool}"
    CFG_TOPIC="homeassistant/sensor/${HA_ID}/config"
    PAYLOAD=$(jq -n \
        --arg name "$HA_LABEL" \
        --arg unique_id "$HA_ID" \
        --arg stat_t "$ZFS_TOPIC" \
        --arg val_tpl "{{ value_json.${POOL_NORM}_health }}" \
        --arg av_t "$AVAIL_TOPIC" \
        --argjson dev "$DEVICE_JSON" \
        '{
            name: $name,
            unique_id: $unique_id,
            object_id: $unique_id,
            state_topic: $stat_t,
            value_template: $val_tpl,
            availability_topic: $av_t,        
            icon: "mdi:database",
            dev: $dev
        }'
    )
    mqtt_publish_retain "$CFG_TOPIC" "$PAYLOAD"
    if [ "$CSV_POOLS_HDR_ADDED" = false ]; then
        CSV_POOLS_HDR+="Pool name"
    fi   
    CSV_POOLS_DATA+="\"${pool}\""

    # --- Health status (binary sensor) ---
    HA_ID="${HOST_NAME}_zfs_${POOL_NORM}_health"
    HA_LABEL="Santé du pool ${pool}"
    CFG_TOPIC="homeassistant/binary_sensor/${HA_ID}/config"
    PAYLOAD=$(jq -n \
        --arg name "$HA_LABEL" \
        --arg unique_id "$HA_ID" \
        --arg stat_t "$ZFS_TOPIC" \
        --arg val_tpl "{{ '0' if value_json.get('${POOL_NORM}_health') == 'ONLINE' else '1' }}" \
        --arg av_t "$AVAIL_TOPIC" \
        --argjson dev "$DEVICE_JSON" \
        '{
            name: $name,
            unique_id: $unique_id,
            object_id: $unique_id,
            payload_on: "1",      
            payload_off: "0",
            state_topic: $stat_t,
            value_template: $val_tpl,
            device_class: "problem",
            availability_topic: $av_t,        
            icon: "mdi:database-check",
            dev: $dev
        }'
    )
    mqtt_publish_retain "$CFG_TOPIC" "$PAYLOAD"
    if [ "$CSV_POOLS_HDR_ADDED" = false ]; then
        CSV_POOLS_HDR+=",Pool health ID"
    fi   
    CSV_POOLS_DATA+=",${HA_ID}"

    # --- Usage percent ---
    HA_ID="${HOST_NAME}_zfs_${POOL_NORM}_usage"
    HA_LABEL="Utilisation du pool ${pool}"
    CFG_TOPIC="homeassistant/sensor/${HA_ID}/config"
    PAYLOAD=$(jq -n \
        --arg name "$HA_LABEL" \
        --arg unique_id "$HA_ID" \
        --arg stat_t "$ZFS_TOPIC" \
        --arg val_tpl "{{ value_json.${POOL_NORM}_usage_percent }}" \
        --arg av_t "$AVAIL_TOPIC" \
        --argjson dev "$DEVICE_JSON" \
        '{
            name: $name,
            unique_id: $unique_id,
            object_id: $unique_id,
            state_topic: $stat_t,
            value_template: $val_tpl,
            unit_of_measurement: "%",
            icon: "mdi:chart-donut",
            availability_topic: $av_t,        
            dev: $dev
        }'
    )
    mqtt_publish_retain "$CFG_TOPIC" "$PAYLOAD"
    if [ "$CSV_POOLS_HDR_ADDED" = false ]; then
        CSV_POOLS_HDR+=",Pool usage ID"
    fi   
    CSV_POOLS_DATA+=",${HA_ID}"

    # --- Free space ---

    HA_ID="${HOST_NAME}_zfs_${POOL_NORM}_free_bytes"
    HA_LABEL="Espace libre du pool ${pool}"
    CFG_TOPIC="homeassistant/sensor/${HA_ID}/config"   
    PAYLOAD=$(jq -n \
        --arg name "$HA_LABEL" \
        --arg unique_id "$HA_ID" \
        --arg stat_t "$ZFS_TOPIC" \
        --arg val_tpl "{{ value_json.${POOL_NORM}_free_bytes }}" \
        --arg av_t "$AVAIL_TOPIC" \
        --argjson dev "$DEVICE_JSON" \
        '{
            name: $name,
            unique_id: $unique_id,
            object_id: $unique_id,
            state_topic: $stat_t,
            value_template: $val_tpl,
            device_class: "data_size",
            state_class: "measurement",
            unit_of_measurement: "B",
            availability_topic: $av_t,        
            icon: "mdi:database-minus",
            dev: $dev
        }'
    )
    mqtt_publish_retain "$CFG_TOPIC" "$PAYLOAD"
    if [ "$CSV_POOLS_HDR_ADDED" = false ]; then
        CSV_POOLS_HDR+=",Free space ID"
    fi   
    CSV_POOLS_DATA+=",${HA_ID}"

    # --- Total size ---
    HA_ID="${HOST_NAME}_zfs_${POOL_NORM}_size_bytes"
    HA_LABEL="Taille du pool ${pool}"
    CFG_TOPIC="homeassistant/sensor/${HA_ID}/config"
    PAYLOAD=$(jq -n \
        --arg name "$HA_LABEL" \
        --arg unique_id "$HA_ID" \
        --arg stat_t "$ZFS_TOPIC" \
        --arg val_tpl "{{ value_json.${POOL_NORM}_size_bytes }}" \
        --arg av_t "$AVAIL_TOPIC" \
        --argjson dev "$DEVICE_JSON" \
        '{
            name: $name,
            unique_id: $unique_id,
            object_id: $unique_id,
            state_topic: $stat_t,
            value_template: $val_tpl,
            device_class: "data_size",
            state_class: "measurement",
            unit_of_measurement: "B",
            availability_topic: $av_t,        
            icon: "mdi:database",
            dev: $dev
        }'
    )
    mqtt_publish_retain "$CFG_TOPIC" "$PAYLOAD"
    if [ "$CSV_POOLS_HDR_ADDED" = false ]; then
        CSV_POOLS_HDR+=",Total size ID"
    fi   
    CSV_POOLS_DATA+=",${HA_ID}"

    # --- Allocated space ---
    HA_ID="${HOST_NAME}_zfs_${POOL_NORM}_allocated_bytes"
    HA_LABEL="Espace alloué du pool ${pool}"
    CFG_TOPIC="homeassistant/sensor/${HA_ID}/config"
    PAYLOAD=$(jq -n \
        --arg name "$HA_LABEL" \
        --arg unique_id "$HA_ID" \
        --arg stat_t "$ZFS_TOPIC" \
        --arg val_tpl "{{ value_json.${POOL_NORM}_allocated_bytes }}" \
        --arg av_t "$AVAIL_TOPIC" \
        --argjson dev "$DEVICE_JSON" \
        '{
            name: $name,
            unique_id: $unique_id,
            object_id: $unique_id,
            state_topic: $stat_t,
            value_template: $val_tpl,
            unit_of_measurement: "B",
            device_class: "data_size",
            state_class: "measurement",
            availability_topic: $av_t,        
            icon: "mdi:database-import",
            dev: $dev
        }'
    )
    mqtt_publish_retain "$CFG_TOPIC" "$PAYLOAD"
    if [ "$CSV_POOLS_HDR_ADDED" = false ]; then
        CSV_POOLS_HDR+=",Allocated space ID"
    fi   
    CSV_POOLS_DATA+=",${HA_ID}"


    # Row finalization
    CSV_POOLS_DATA+=$'\n'    

    # Header record finalization
    if [ "$CSV_POOLS_HDR_ADDED" = false ]; then
        CSV_POOLS_HDR+=$'\n'    
        CSV_POOLS_HDR_ADDED=true
    fi   

done

# On confirme la disponibilité du NAS
mqtt_publish_retain "$AVAIL_TOPIC" "online"

log_debug "--- DISCOVERY COMPLETE ---"

# --- Test mode ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    [[ "$DEBUG" == "true" ]] && echo "--- NAS DISCOVERY TEST ---"
    [[ "$DEBUG" == "true" ]] && echo "NVMe devices discovered:"
    if [[ "$DEBUG" == "true" ]]; then
        for hw_path in /sys/class/hwmon/hwmon*; do
            hw_name=$(cat "$hw_path/name" 2>/dev/null || echo "")
            [[ "$hw_name" == "nvme" ]] || continue
            nvme_link=$(readlink -f "$hw_path")
            nvme_dev=$(echo "$nvme_link" | grep -oP 'nvme\d+' | head -n1)
            SN=$(cat "/sys/class/nvme/$nvme_dev/serial" 2>/dev/null | tr -d ' ')
            MODEL=$(cat "/sys/class/nvme/$nvme_dev/model" 2>/dev/null | tr -d ' ' || echo "NVMe")
            echo "  $nvme_dev: $MODEL (S/N: $SN)"
        done
        echo "--- END OF TEST ---"
        echo ""
        echo "CSV Fragments to be given to an IA to generate HomeAssitstant dashboards cards"
        echo ""
        echo "--- BEGIN OF NVMe CSV ---"
        echo "$CSV_LINES" 
        echo "--- END OF NVMe CSV ---"

        echo "--- ZFS Pools CSV Fragment ---"
        echo "# Data map for Home Assistant entity IDs on host ${HOST_NAME} avec ApexCharts si besoin"
        echo "$CSV_POOLS_HDR"
        echo "$CSV_POOLS_DATA"
        echo "--- END OF ZFS POOLS CSV ---"

    fi
fi
