#!/bin/bash

#
    box_line "Reached after CPU config publish" "LIGHTGRAY"
# @file /usr/local/bin/sentrylab/discovery.sh
# @author CmPi <cmpi@webe.fr>
# @brief Publishes NAS sensors to Home Assistant for automatic discovery
# @date 2025-12-28
# @version 1.0.362.5
# @usage Run at boot to register Home Assistant sensors
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

# Show failing command and location when run interactively
if [[ "${INTERACTIVE:-false}" == "true" ]]; then
    trap 'ec=$?; box_line "ERROR: ${BASH_COMMAND} failed at ${BASH_SOURCE[0]}:${LINENO} (exit ${ec})" RED; exit ${ec}' ERR
fi

box_title "SentryLab Discovery Script (simulation mode)"

# === Broker MQTT Availability ===

box_begin "MQTT Broker Availability"

MAX_RETRIES=40
RETRY_COUNT=0

box_line "Checking MQTT Broker availability ($BROKER:$PORT)..."

# nc (netcat) vérifie si le port est ouvert sans envoyer de données
while ! nc -z "$BROKER" "$PORT"; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        box_line "ERROR: Broker unreachable after $MAX_RETRIES attempts. Exiting."
        box_end
        exit 1
    fi
    box_line "SKIP: Broker not ready... retrying in 10s ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 15
done
box_line "INFO: Broker is UP! Proceeding with discovery."
box_end

# --- Enable nullglob for NVMe temperature sensors et pools enumaration ---
shopt -s nullglob

# --- Device JSON pour Home Assistant ---
DEVICE_JSON=$(jq -n --arg hn "$HOST_NAME" '{"identifiers": [$hn], "name": $hn, "model": "Node", "manufacturer": "Proxmox"}')
BASE_CONFIG=$(jq -n --argjson dev "$DEVICE_JSON" --arg av_t "$AVAIL_TOPIC" '{availability_topic: $av_t, dev: $dev}')

# --- Initialisation du JSON pour la publication MQTT ---
JSON=$(jq -n '{}')

# --- CSVs for IA dashboard generation ---

CSV_LINES="HA_ID,Type,Label,Serial,Slot"$'\n'

CSV_POOLS_HDR=""
CSV_POOLS_DATA=""
CSV_POOLS_HDR_ADDED=false

CSV_DISKS_HDR=""
CSV_DISKS_DATA=""

# --- CSVs for IA dashboard generation ---
CSV_SYSTEM_HDR=""
CSV_SYSTEM_DATA=""

if [[ "$PUSH_SYSTEM" == "true" ]]; then

    box_begin "System Sensors"

    CSV_SYSTEM_HDR="HomeAssistant entity ID,Metric name in english,Metric name in french"

    # --- 1. Register CPU sensor ---

    # include hostname in HA ID (to avoid conflicts if other NAS or Workstations report their CPU temperature)

    box_line ""
    box_line "CPU temperature"
    HA_ID="${HOST_NAME}_cpu_temp"
    HA_LABEL=$(translate "cpu_temp")
    CFG_TOPIC="homeassistant/sensor/${HA_ID}/config"
    PAYLOAD=$(jq -n \
        --arg name "$HA_LABEL" \
        --arg unique_id "$HA_ID" \
        --arg stat_t "$TEMP_TOPIC" \
        --arg val_tpl '{{ value_json.cpu }}' \
        --arg availability "$AVAIL_TOPIC" \
        --argjson dev "$DEVICE_JSON" \
        '{ 
            name: $name, 
            unique_id: $unique_id, 
            object_id: $unique_id,
            state_topic: $stat_t,
            value_template: $val_tpl,
            unit_of_measurement: "°C", icon: "mdi:thermometer",
            device_class: "temperature",
            availability_topic: $availability,        
            dev: $dev
        }'
    )

    box_line "before"
    mqtt_publish_retain "$CFG_TOPIC" "$PAYLOAD"
    box_line "after"

    CSV_SYSTEM_DATA+="${HA_ID},CPU temperature,Température du CPU"$'\n'

    # --- 2. Register Chassis temperature sensor (not CPU related, I know) ---

    # include hostname in HA ID (to avoid conflicts if other NAS or Workstations report their CPU temperature)

    box_line "Chassis temperature" "MAGENTA"

    HA_ID="${HOST_NAME}_chassis_temp"
    HA_LABEL="Température du chassis"
    CFG_TOPIC="homeassistant/sensor/${HA_ID}/config"
    PAYLOAD=$(jq -n \
        --arg name "$HA_LABEL" \
        --arg unique_id "$HA_ID" \
        --arg stat_t "$TEMP_TOPIC" \
        --arg val_tpl '{{ value_json.chassis }}' \
        --arg av_t "$AVAIL_TOPIC" \
        --argjson dev "$DEVICE_JSON" \
        '{
            name: $name,
            unique_id: $unique_id,
            object_id: $unique_id,
            state_topic: $stat_t,
            value_template: $val_tpl,
            unit_of_measurement: "°C",
            icon: "mdi:thermometer",
            device_class: "temperature",
            availability_topic: $av_t,        
            dev: $dev
        }'
    )
    mqtt_publish_retain "$CFG_TOPIC" "$PAYLOAD"
    box_line "Reached after Chassis config publish" "LIGHTGRAY"
    CSV_SYSTEM_DATA+="${HA_ID},Chassis temperature,Température du chassis"$'\n'

    # --- CPU Cores (Static) ---
    if command -v nproc >/dev/null; then
        CPU_CORES=$(nproc)
        HA_ID="${HOST_NAME}_cpu_cores"
        HA_LABEL="Nombre de Coeurs CPU"
        CFG_TOPIC="homeassistant/sensor/${HA_ID}/config"
        PAYLOAD=$(jq -n \
            --arg name "$HA_LABEL" \
            --arg unique_id "$HA_ID" \
            --arg stat_t "$SYSTEM_TOPIC" \
            --arg val_tpl '{{ value_json.cpu_cores }}' \
            --arg icon "mdi:cpu-64-bit" \
            --arg av_t "$AVAIL_TOPIC" \
            --argjson dev "$DEVICE_JSON" \
            '{name: $name, unique_id: $unique_id, object_id: $unique_id, state_topic: $stat_t, value_template: $val_tpl, icon: $icon, availability_topic: $av_t, dev: $dev}')
        mqtt_publish_retain "$CFG_TOPIC" "$PAYLOAD"
        CSV_SYSTEM_DATA+="${HA_ID},Cores,Nombre de Coeurs CPU"$'\n'
        box_line "CPU Cores registered ($CPU_CORES)"
    fi

    # --- CPU Load Average (5 min) ---
    if [[ -f /proc/loadavg ]]; then
        HA_ID="${HOST_NAME}_cpu_load_5m"
        HA_LABEL=$(translate "cpu_load_5m")
        CFG_TOPIC="homeassistant/sensor/${HA_ID}/config"
        PAYLOAD=$(jq -n \
            --arg name "$HA_LABEL" \
            --arg unique_id "$HA_ID" \
            --arg stat_t "$SYSTEM_TOPIC" \
            --arg val_tpl '{{ value_json.cpu_load_5m }}' \
            --arg icon "mdi:speedometer-medium" \
            --arg av_t "$AVAIL_TOPIC" \
            --argjson dev "$DEVICE_JSON" \
            '{name: $name, unique_id: $unique_id, object_id: $unique_id, state_topic: $stat_t, value_template: $val_tpl, icon: $icon, availability_topic: $av_t, dev: $dev}')
        
        mqtt_publish_retain "$CFG_TOPIC" "$PAYLOAD"
        CSV_SYSTEM_DATA+="${HA_ID},Load (5m),Charge CPU (5 min)"$'\n'
        box_line "CPU Load (5mn): Registered"
    fi

    # --- Memory Total ---
    HA_ID="${HOST_NAME}_mem_total"
    HA_LABEL=$(translate "mem_total")
    CFG_TOPIC="homeassistant/sensor/${HA_ID}/config"
    PAYLOAD=$(jq -n \
        --arg name "$HA_LABEL" \
        --arg unique_id "$HA_ID" \
        --arg stat_t "$SYSTEM_TOPIC" \
        --arg val_tpl '{{ value_json.mem_total_mb }}' \
        --arg icon "mdi:memory" \
        --arg av_t "$AVAIL_TOPIC" \
        --argjson dev "$DEVICE_JSON" \
        '{name: $name, unique_id: $unique_id, object_id: $unique_id, state_topic: $stat_t, value_template: $val_tpl, unit_of_measurement: "MB", icon: $icon, availability_topic: $av_t, dev: $dev}')
    mqtt_publish_retain "$CFG_TOPIC" "$PAYLOAD"
    CSV_SYSTEM_DATA+="${HA_ID},Memory Total,Mémoire totale"$'\n'
    box_line "Memory Total: Registered"

    # --- Memory Used ---
    HA_ID="${HOST_NAME}_mem_used"
    HA_LABEL=$(translate "mem_used")
    CFG_TOPIC="homeassistant/sensor/${HA_ID}/config"
    PAYLOAD=$(jq -n \
        --arg name "$HA_LABEL" \
        --arg unique_id "$HA_ID" \
        --arg stat_t "$SYSTEM_TOPIC" \
        --arg val_tpl '{{ value_json.mem_used_mb }}' \
        --arg icon "mdi:memory" \
        --arg av_t "$AVAIL_TOPIC" \
        --argjson dev "$DEVICE_JSON" \
        '{name: $name, unique_id: $unique_id, object_id: $unique_id, state_topic: $stat_t, value_template: $val_tpl, unit_of_measurement: "MB", icon: $icon, availability_topic: $av_t, dev: $dev}')
    mqtt_publish_retain "$CFG_TOPIC" "$PAYLOAD"
    CSV_SYSTEM_DATA+="${HA_ID},Memory Used,Mémoire utilisée"$'\n'
    box_line "Memory Used: Registered"

    # --- Memory Usage Percentage ---
    HA_ID="${HOST_NAME}_mem_usage_percent"
    HA_LABEL=$(translate "mem_usage_percent")
    CFG_TOPIC="homeassistant/sensor/${HA_ID}/config"
    PAYLOAD=$(jq -n \
        --arg name "$HA_LABEL" \
        --arg unique_id "$HA_ID" \
        --arg stat_t "$SYSTEM_TOPIC" \
        --arg val_tpl '{{ value_json.mem_usage_percent }}' \
        --arg icon "mdi:percent" \
        --arg av_t "$AVAIL_TOPIC" \
        --argjson dev "$DEVICE_JSON" \
        '{name: $name, unique_id: $unique_id, object_id: $unique_id, state_topic: $stat_t, value_template: $val_tpl, unit_of_measurement: "%", icon: $icon, availability_topic: $av_t, dev: $dev}')
    mqtt_publish_retain "$CFG_TOPIC" "$PAYLOAD"
    CSV_SYSTEM_DATA+="${HA_ID},Memory Usage %,Pourcentage mémoire"$'\n'
    box_line "Memory Usage %: Registered"

    # --- Thermal Throttle Count ---
    HA_ID="${HOST_NAME}_throttle_count"
    HA_LABEL=$(translate "throttle_count")
    CFG_TOPIC="homeassistant/sensor/${HA_ID}/config"
    PAYLOAD=$(jq -n \
        --arg name "$HA_LABEL" \
        --arg unique_id "$HA_ID" \
        --arg stat_t "$SYSTEM_TOPIC" \
        --arg val_tpl '{{ value_json.throttle_count }}' \
        --arg icon "mdi:thermometer-alert" \
        --arg av_t "$AVAIL_TOPIC" \
        --argjson dev "$DEVICE_JSON" \
        '{name: $name, unique_id: $unique_id, object_id: $unique_id, state_topic: $stat_t, value_template: $val_tpl, icon: $icon, availability_topic: $av_t, dev: $dev}')
    mqtt_publish_retain "$CFG_TOPIC" "$PAYLOAD"
    CSV_SYSTEM_DATA+="${HA_ID},Throttle Events,Événements de limitation thermique"$'\n'
    box_line "Thermal Throttle Count: Registered"

    # --- CPU Max Frequency ---
    HA_ID="${HOST_NAME}_cpu_max_freq"
    HA_LABEL=$(translate "cpu_max_freq")
    CFG_TOPIC="homeassistant/sensor/${HA_ID}/config"
    PAYLOAD=$(jq -n \
        --arg name "$HA_LABEL" \
        --arg unique_id "$HA_ID" \
        --arg stat_t "$SYSTEM_TOPIC" \
        --arg val_tpl '{{ value_json.cpu_max_freq_mhz }}' \
        --arg icon "mdi:speedometer" \
        --arg av_t "$AVAIL_TOPIC" \
        --argjson dev "$DEVICE_JSON" \
        '{name: $name, unique_id: $unique_id, object_id: $unique_id, state_topic: $stat_t, value_template: $val_tpl, unit_of_measurement: "MHz", icon: $icon, availability_topic: $av_t, dev: $dev}')
    mqtt_publish_retain "$CFG_TOPIC" "$PAYLOAD"
    CSV_SYSTEM_DATA+="${HA_ID},CPU Max Frequency,Fréquence CPU max"$'\n'
    box_line "CPU Max Frequency: Registered"

    # --- CPU Current Frequency ---
    HA_ID="${HOST_NAME}_cpu_current_freq"
    HA_LABEL=$(translate "cpu_current_freq")
    CFG_TOPIC="homeassistant/sensor/${HA_ID}/config"
    PAYLOAD=$(jq -n \
        --arg name "$HA_LABEL" \
        --arg unique_id "$HA_ID" \
        --arg stat_t "$SYSTEM_TOPIC" \
        --arg val_tpl '{{ value_json.cpu_current_freq_mhz }}' \
        --arg icon "mdi:speedometer" \
        --arg av_t "$AVAIL_TOPIC" \
        --argjson dev "$DEVICE_JSON" \
        '{name: $name, unique_id: $unique_id, object_id: $unique_id, state_topic: $stat_t, value_template: $val_tpl, unit_of_measurement: "MHz", icon: $icon, availability_topic: $av_t, dev: $dev}')
    mqtt_publish_retain "$CFG_TOPIC" "$PAYLOAD"
    CSV_SYSTEM_DATA+="${HA_ID},CPU Current Frequency,Fréquence CPU actuelle"$'\n'
    box_line "CPU Current Frequency: Registered"

    box_end

fi

# --- 3. Register NVMe sensors for Home Assistant discovery ---

# do not include hostname in NVMe HA ID:
#  * S/N should be unique
#  * they mght be moved to another machine
# benefit: after a move, their history in HA is preserved

box_begin "NVMe Sensors"

if [[ "$PUSH_NVME_WEAR" != "true" ]]; then
    box_value "Wear" "disabled (PUSH_NVME_WEAR!=true)"
fi
if [[ "$PUSH_NVME_HEALTH" != "true" ]]; then
    box_value "Health" "disabled (PUSH_NVME_HEALTH!=true)"
fi
if [[ "$PUSH_NVME_TEMP" != "true" ]]; then
    box_value "Temperature" "disabled (PUSH_NVME_TEMP!=true)"
fi

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
    box_value "$NVME_SLOT_ID" "S/N $SN - P/N $MODEL"

    # --- Wear sensor ---
    if [[ "$PUSH_NVME_WEAR" == "true" ]]; then
        HA_ID="nvme_${SN_LOWER}_wear"
        HA_LABEL="$(translate "nvme_wear") ${SN}"
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
    fi

    if [[ "$PUSH_NVME_HEALTH" == "true" ]]; then
        # --- Health binary sensor ---
        HA_ID="nvme_${SN_LOWER}_health"
        HA_LABEL="$(translate "nvme_health") ${SN} (slot ${NVME_SLOT_ID})"
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
    fi

    if [[ "$PUSH_NVME_TEMP" == "true" ]]; then
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
            HA_LABEL="$(translate "nvme_temp") ${label_display} du SSD ${SN}"
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
    fi

done

box_end

# --- ZFS pools discovery ---

if [[ "$PUSH_ZFS" == "true" ]]; then

    box_begin "Pools ZFS ${POOLS}"


    POOLS=$(zpool list -H -o name 2>/dev/null || true)
    if [[ -z "$POOLS" ]]; then
        log_debug "No ZFS pools found"
    else

        for pool in $POOLS; do
            POOL_NORM=$(echo "$pool" | tr '-' '_' | tr '[:upper:]' '[:lower:]')

            log_debug "Registering ZFS pools: $pool"

            # --- Health (sensor) ---
            HA_ID="${HOST_NAME}_zfs_${POOL_NORM}_status"
            HA_LABEL="$(translate "zfs_pool_status") ${pool}"
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
            HA_LABEL="$(translate "zfs_pool_health") ${pool}"
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
            HA_LABEL="$(translate "zfs_pool_usage") ${pool}"
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
            HA_LABEL="$(translate "zfs_pool_free") ${pool}"
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
            HA_LABEL="$(translate "zfs_pool_size") ${pool}"
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
            HA_LABEL="$(translate "zfs_pool_allocated") ${pool}"
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

    fi

    box_end

fi


# --- 4. Processing: Non-ZFS Disks ---

if [[ "$PUSH_NON_ZFS" == "true" ]]; then

    box_begin "Standard Partitions Discovery"

    CSV_DISKS_HDR="Mountpoint,FSType,Free_Space_ID,Total_Size_ID"
    CSV_DISKS_DATA=""

    while read -r target fstype; do
        # ID normalisé
        DISK_ID=$(echo "$target" | tr '/' '_' | sed 's/^_//;s/^$/root/')
        
        HA_FREE_ID="${HOST_NAME}_disk_${DISK_ID}_free_bytes"
        HA_SIZE_ID="${HOST_NAME}_disk_${DISK_ID}_size_bytes"

        # Skip non-pertinent pseudo or tiny filesystems (eg. efivars)
        case "$fstype" in
            efivarfs|proc|sysfs|devpts|cgroup*|debugfs|tracefs|configfs|squashfs|overlay)
                box_line "SKIP: non-pertinent fstype $fstype for $target"
                continue
                ;;
        esac

        # Skip mountpoints under sys, proc, dev, run (commonly ephemeral or system)
        if [[ "$target" == /sys/* || "$target" == /proc/* || "$target" == /dev/* || "$target" == /run/* ]]; then
            box_line "SKIP: mountpoint $target appears system-managed"
            continue
        fi

        # 1. Publication MQTT (Seulement le brut)
        # Capteur Libre
        PAYLOAD_F=$(jq -n --arg name "Libre ${target}" --arg id "$HA_FREE_ID" --arg st "$DISK_TOPIC" --arg v "value_json.${DISK_ID}_free_bytes" --arg av "$AVAIL_TOPIC" --argjson dev "$DEVICE_JSON" \
            '{name: $name, unique_id: $id, object_id: $id, state_topic: $st, value_template: ("{{ " + $v + " }}"), device_class: "data_size", unit_of_measurement: "B", availability_topic: $av, dev: $dev}')
        mqtt_publish_retain "homeassistant/sensor/${HA_FREE_ID}/config" "$PAYLOAD_F"

        # Capteur Total
        PAYLOAD_T=$(jq -n --arg name "Total ${target}" --arg id "$HA_SIZE_ID" --arg st "$DISK_TOPIC" --arg v "value_json.${DISK_ID}_size_bytes" --arg av "$AVAIL_TOPIC" --argjson dev "$DEVICE_JSON" \
            '{name: $name, unique_id: $id, object_id: $id, state_topic: $st, value_template: ("{{ " + $v + " }}"), device_class: "data_size", unit_of_measurement: "B", availability_topic: $av, dev: $dev}')
        mqtt_publish_retain "homeassistant/sensor/${HA_SIZE_ID}/config" "$PAYLOAD_T"

        # 2. Construction de la donnée CSV
        CSV_DISKS_DATA+=$'\n'"\"${target}\",${fstype},${HA_FREE_ID},${HA_SIZE_ID}"

        # Debug visuel dans tes boîtes (label/value)
        box_value "Registered" "$target" 80

    done < <(df -x tmpfs -x devtmpfs -x zfs --output=target,fstype | tail -n +2)

    box_end

fi

box_begin "Availability Confirmation"

# Confirm NAS availability
mqtt_publish_retain "$AVAIL_TOPIC" "online"

box_end




# --- 5. CSV Export Section ---

if [[ -n "${OUTPUT_CSV_DIR:-}" ]]; then
    box_begin "CSV EXPORTS"
    box_value "ZFS"      "$(write_csv "zfs.csv" "$CSV_POOLS_HDR" "$CSV_POOLS_DATA")"
    box_value "Standard" "$(write_csv "standard_disks.csv" "$CSV_DISKS_HDR" "$CSV_DISKS_DATA")"
    box_value "NVMe"     "$(write_csv "nvme.csv" "$CSV_LINES")"
    box_end
fi