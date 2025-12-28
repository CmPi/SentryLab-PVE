#!/bin/bash

#
# @file /usr/local/bin/sentrylab/utils.sh
# @author CmPi <cmpi@webe.fr>
# @brief Global functions for SentryLab-PVE
# @date 2025-12-27
# @version 1.1.361
# @usage source "$(dirname "$0")/utils.sh"
# @notes * make it executable as usual using the command:
#          chmod +x /usr/local/bin/sentrylab/*.sh
#        * run it as a script to display current configuration
#        * otherwise let the other SentryLab scrips source it for functions 
#       

set -euo pipefail

# --- Log error messages
log_error() {
    echo "ERROR: $*" >&2
}

# --- Dynamic Path Logic ---
# Prioritize /usr/local/etc for production, then local project root for dev
if [ -f "/usr/local/etc/sentrylab.conf" ]; then
    CONFIG_PATH="/usr/local/etc/sentrylab.conf"
else
    log_error "Configuration file not found (sentrylab.conf or config.conf)!"
    exit 1
fi

source "$CONFIG_PATH"

# --- MQTT Topics (Derived from config) ---
BASE_TOPIC="proxmox/${HOST_NAME}"
TEMP_TOPIC="$BASE_TOPIC/temp"
WEAR_TOPIC="$BASE_TOPIC/wear"
HEALTH_TOPIC="$BASE_TOPIC/health"
ZFS_TOPIC="$BASE_TOPIC/zfs"
AVAIL_TOPIC="$BASE_TOPIC/availability"
HA_DISCOVERY_PREFIX="${HA_BASE_TOPIC:-homeassistant}"

# === Functions ===

log_debug() {
    [[ "${DEBUG:-false}" == "true" ]] && echo "DEBUG: $*"
}

# --- Publish with RETAIN (Configs, ZFS/NVMe Health)
mqtt_publish_retain() {
    local topic="$1"
    local payload="$2"

    [[ -z "$topic" || -z "$payload" ]] && { log_error "Topic or payload empty"; return 1; }

    if [[ "${DEBUG:-false}" == "true" ]]; then
        log_debug "Would publish (RETAIN) to $topic -> $payload"
    else
        if mosquitto_pub -h "$BROKER" -p "$PORT" \
                         -u "$USER" -P "$PASS" \
                         -t "$topic" -m "$payload" -r -q 1; then
            log_debug "Published (Retain) to $topic"
        else
            log_error "Failed to publish to $topic"
            return 1
        fi
    fi
}

# --- Publish WITHOUT RETAIN (Temperatures)
mqtt_publish_no_retain() {
    local topic="$1"
    local payload="$2"

    [[ -z "$topic" || -z "$payload" ]] && { log_error "Topic or payload empty"; return 1; }

    if [[ "${DEBUG:-false}" == "true" ]]; then
        log_debug "Would publish (NO-RETAIN) to $topic -> $payload"
    else
        if mosquitto_pub -h "$BROKER" -p "$PORT" \
                         -u "$USER" -P "$PASS" \
                         -t "$topic" -m "$payload" \
                         --will-topic "$AVAIL_TOPIC" \
                         --will-payload "offline" \
                         --will-retain \
                         -q 1; then
            log_debug "Published (No-Retain) to $topic"
        else
            log_error "Failed to publish to $topic"
            return 1
        fi
    fi
}

# --- Write CSV with backup ---
# Usage: write_csv "filename.csv" "content"
# - Writes to OUTPUT_CSV_DIR if defined and content is not empty
# - Creates OUTPUT_CSV_DIR if necessary
# - Backs up existing file to filename.csv.bak
# - Debug mode logs actions
write_csv() {
    local csv_file="$1"
    local csv_content="$2"

    # Skip if OUTPUT_CSV_DIR is not defined
    [[ -z "${OUTPUT_CSV_DIR:-}" ]] && return 0

    # Do not create file if content is empty
    if [[ -z "$csv_content" ]]; then
        log_debug "CSV content is empty, skipping file '$csv_file'"
        return 0
    fi

    # Ensure output directory exists
    if [ ! -d "$OUTPUT_CSV_DIR" ]; then
        mkdir -p "$OUTPUT_CSV_DIR" || { log_debug "Failed to create OUTPUT_CSV_DIR: $OUTPUT_CSV_DIR"; return 1; }
        log_debug "Created OUTPUT_CSV_DIR: $OUTPUT_CSV_DIR"
    fi

    local full_path="$OUTPUT_CSV_DIR/$csv_file"

    # Backup existing file if it exists
    if [ -f "$full_path" ]; then
        local backup_path="$full_path.bak"
        mv "$full_path" "$backup_path" || { log_debug "Failed to backup existing CSV to $backup_path"; return 1; }
        log_debug "Existing CSV backed up to '$backup_path'"
    fi

    # Write new CSV
    printf '%s\n' "$csv_content" > "$full_path" || { log_debug "Failed to write CSV to $full_path"; return 1; }

    log_debug "CSV file created at '$full_path'"
}


# --- Display loaded configuration when run directly ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "--- SentryLab-PVE Utils Configuration ---"
    echo "Broker: $BROKER:$PORT"
    echo "Host: $HOST_NAME"
    echo "HA Discovery Prefix: $HA_DISCOVERY_PREFIX"
    echo "CSV export directory: ${OUTPUT_CSV_DIR:-not defined}"
    echo "Feature toggles:"
    echo "  PUSH_ZFS=$PUSH_ZFS"
    echo "  PUSH_TEMP=$PUSH_TEMP"
    echo "  PUSH_NVME_WEAR=$PUSH_NVME_WEAR"
    echo "  PUSH_NVME_HEALTH=$PUSH_NVME_HEALTH"
    echo "  PUSH_NON_ZFS=$PUSH_NON_ZFS"
    echo "--- End of configuration ---"
fi
