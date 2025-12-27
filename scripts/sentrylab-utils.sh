#!/bin/bash

#
# @file /usr/local/bin/sentrylab-utils.sh
# @author CmPi <cmpi@webe.fr>
# @brief Global functions for SentryLab-PVE
# @date 2025-12-27
# @version 1.1.361
# @usage source "$(dirname "$0")/sentrylab-utils.sh"
# @notes * make it executable as usual using the command:
#          chmod +x /usr/local/bin/*.sh
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
elif [ -f "$(dirname "$0")/../config.conf" ]; then
    CONFIG_PATH="$(dirname "$0")/../config.conf"
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

# --- Test mode ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "--- SentryLab-PVE Utils Test ($BASH_SOURCE) ---"
    echo "Version: 1.1.361"
    echo "Broker: $BROKER:$PORT"
    echo "Host: $HOST_NAME"
    echo "HA Prefix: $HA_DISCOVERY_PREFIX"
    echo "--- End of Test ---"
fi