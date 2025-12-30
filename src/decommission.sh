#!/bin/bash

#
# @file decommission.sh
# @author CmPi <cmpi@webe.fr>
# @repo https://github.com/CmPi/SentryLab-PVE
# @brief Cleanup MQTT topics for a decommissioned host
# @date creation 2025-12-30
# @version 1.0.365
# @usage ./decommission.sh <platform> <host_name>
# @example ./decommission.sh proxmox myserver
#          ./decommission.sh windows myworkstation
#          ./decommission.sh esp32 witty-display
#

set -euo pipefail

# Load shared utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/utils.sh" ]; then
    source "$SCRIPT_DIR/utils.sh"
else
    echo "ERROR: Required file '$SCRIPT_DIR/utils.sh' not found." >&2
    exit 1
fi

# Check parameters
if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <platform> <host_name>"
    echo ""
    echo "Parameters:"
    echo "  platform   : windows | proxmox | esp32"
    echo "  host_name  : Name of the host to decommission"
    echo ""
    echo "Example:"
    echo "  $0 proxmox myserver"
    exit 1
fi

PLATFORM="$1"
DECOMM_HOST="$2"

# Validate platform
case "$PLATFORM" in
    windows|proxmox|esp32)
        ;;
    *)
        echo "ERROR: Invalid platform '$PLATFORM'. Must be: windows, proxmox, or esp32"
        exit 1
        ;;
esac

box_begin "SentryLab Host Decommissioning"
box_line "Platform: $PLATFORM" "CYAN"
box_line "Host: $DECOMM_HOST" "CYAN"
box_line ""
box_line "WARNING: This will delete ALL MQTT topics for this host!" "RED"
box_line "This includes all sensor data and Home Assistant discovery configs." "RED"
box_line ""

# Confirmation prompt
if [[ "${DEBUG:-false}" != "true" ]]; then
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        box_line "Decommission cancelled by user" "YELLOW"
        box_end
        exit 0
    fi
fi

box_end

# Build base topic
BASE_TOPIC_DECOMM="${PLATFORM}/${DECOMM_HOST}"

box_begin "Cleaning Platform Topics"
box_line "Base topic: $BASE_TOPIC_DECOMM"

# List of common topics to clean (platform agnostic)
TOPICS_TO_CLEAN=(
    "$BASE_TOPIC_DECOMM/availability"
    "$BASE_TOPIC_DECOMM/system"
    "$BASE_TOPIC_DECOMM/temp"
    "$BASE_TOPIC_DECOMM/wear"
    "$BASE_TOPIC_DECOMM/health"
    "$BASE_TOPIC_DECOMM/zfs"
    "$BASE_TOPIC_DECOMM/disks"              # Old schema (v1.0.363): single JSON with all disks
    "$BASE_TOPIC_DECOMM/disks/states"        # New schema (v1.0.365): all power states
)

# Platform-specific additional topics
if [[ "$PLATFORM" == "proxmox" ]]; then
    # Note: temp, wear, health are single topics with JSON payloads
    # Individual NVMe properties are extracted via value_template in HA
    # No need to delete per-property topics - they don't exist
    :
fi

# Clean up platform topics
CLEANED_COUNT=0
FAILED_COUNT=0

for topic in "${TOPICS_TO_CLEAN[@]}"; do
    if mqtt_delete_retained "$topic"; then
        ((CLEANED_COUNT++))
        box_line "✓ $topic" "GREEN"
    else
        ((FAILED_COUNT++))
        box_line "✗ $topic" "RED"
    fi
done

box_line ""
box_value "Cleaned" "$CLEANED_COUNT topics"
box_value "Failed" "$FAILED_COUNT topics"

box_end

box_begin "Cleaning Per-Disk Topics"

# For disk topics, we need to discover what disks were registered
# This is tricky without knowing the disk IDs, but we can try common ones
COMMON_DISK_IDS=("root" "data" "backup" "storage" "media" "home" "boot" "var" "tmp")

DISK_CLEANED=0
for disk_id in "${COMMON_DISK_IDS[@]}"; do
    # New schema (v1.0.365): per-disk topics
    topics=(
        "$BASE_TOPIC_DECOMM/disk/${disk_id}"
    )
    for topic in "${topics[@]}"; do
        if mqtt_delete_retained "$topic"; then
            ((DISK_CLEANED++))
            box_line "✓ $topic (v1.0.365 schema)" "GREEN"
        fi
    done
done

box_line ""
box_value "Disk topics cleaned" "$DISK_CLEANED"
box_line "NOTE: Only common disk IDs checked. Manual cleanup may be needed." "YELLOW"
box_line "NOTE: Old schema (v1.0.363) '$BASE_TOPIC_DECOMM/disks' cleaned above." "YELLOW"

box_end

box_begin "Cleaning Home Assistant Discovery Configs"

# Home Assistant discovery topics follow pattern:
# homeassistant/sensor/<host_name>_<sensor_name>/config
# homeassistant/binary_sensor/<host_name>_<sensor_name>/config

# Common sensor patterns for both platforms
HA_SENSOR_PATTERNS=(
    "cpu_temp"
    "chassis_temp"
    "cpu_cores"
    "cpu_load_5m"
    "mem_total"
    "mem_used"
    "mem_usage_percent"
    "throttle_count"
    "cpu_max_freq"
    "cpu_current_freq"
)

# Platform-specific patterns
if [[ "$PLATFORM" == "proxmox" ]]; then
    # Add NVMe temp/wear/health sensors (up to 10 devices)
    for i in {0..9}; do
        HA_SENSOR_PATTERNS+=(
            "temp_nvme${i}"
            "wear_nvme${i}_wearout"
            "wear_nvme${i}_data_written_tb"
            "health_nvme${i}_critical_warning"
            "health_nvme${i}_media_errors"
            "health_nvme${i}_percent_used"
        )
    done
    # Add ZFS pool sensors (common pool names)
    for pool in "rpool" "tank" "data" "backup" "storage"; do
        HA_SENSOR_PATTERNS+=(
            "zfs_${pool}_status"
            "zfs_${pool}_health"
            "zfs_${pool}_usage"
            "zfs_${pool}_free_bytes"
            "zfs_${pool}_size_bytes"
            "zfs_${pool}_allocated_bytes"
        )
    done
    # Add disk sensors (common disk IDs)
    for disk_id in "${COMMON_DISK_IDS[@]}"; do
        HA_SENSOR_PATTERNS+=(
            "disk_${disk_id}_free_bytes"
            "disk_${disk_id}_size_bytes"
            "disk_${disk_id}_power_state"
        )
    done
fi

HA_CLEANED=0
HA_FAILED=0

# Clean sensor configs
for pattern in "${HA_SENSOR_PATTERNS[@]}"; do
    topic="${HA_DISCOVERY_PREFIX}/sensor/${DECOMM_HOST}_${pattern}/config"
    if mqtt_delete_retained "$topic"; then
        ((HA_CLEANED++))
        box_line "✓ $topic" "GREEN"
    else
        ((HA_FAILED++))
    fi
done

# Clean binary sensor configs (if any)
# Note: Currently no binary sensors, but structure is ready for future

box_line ""
box_value "HA discovery configs cleaned" "$HA_CLEANED"
box_value "HA configs failed" "$HA_FAILED"
box_line "NOTE: Only known patterns cleaned. Check MQTT broker for remaining topics." "YELLOW"

box_end

box_begin "Decommission Summary"
box_line "Platform: $PLATFORM / Host: $DECOMM_HOST" "CYAN"
box_value "Platform topics" "$CLEANED_COUNT cleaned, $FAILED_COUNT failed"
box_value "Disk topics" "$DISK_CLEANED cleaned"
box_value "HA discovery" "$HA_CLEANED cleaned, $HA_FAILED failed"
box_line ""
box_line "Decommissioning complete!" "GREEN"
box_line ""
box_line "Next steps:" "CYAN"
box_line "1. Check Home Assistant for orphaned entities" "YELLOW"
box_line "2. Remove any remaining manual MQTT topics in broker" "YELLOW"
box_line "3. Update your dashboards and automations" "YELLOW"
box_end
