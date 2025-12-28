#!/bin/bash

#
# @file /usr/local/bin/sentrylab/utils.sh
# @author CmPi <cmpi@webe.fr>
# @brief Global functions for SentryLab-PVE
# @date 2025-12-28
# @version 1.1.361
# @usage source "$(dirname "$0")/utils.sh"
# @notes * Make it executable: chmod +x /usr/local/bin/sentrylab/*.sh
#        * Run directly to display current configuration
#        * Sourced from other SentryLab scripts for functions and configuration loading
#

set -euo pipefail

# ==============================================================================
# LOGGING FUNCTIONS
# ==============================================================================

# Log error messages to stderr
log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

# Log debug messages (only when DEBUG=true)
log_debug() {
    [[ "${DEBUG:-false}" == "true" ]] && echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

# Log info messages
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

# Log warning messages
log_warn() {
    echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

# ==============================================================================
# CONFIGURATION LOADING
# ==============================================================================

# Load configuration file with validation
load_config() {
    local config_paths=(
        "/usr/local/etc/sentrylab.conf"
        "./sentrylab.conf"
    )

    local config_found=false
    for config_path in "${config_paths[@]}"; do
        if [[ -f "$config_path" ]]; then
            CONFIG_PATH="$config_path"
            # shellcheck source=/dev/null
            source "$CONFIG_PATH"
            config_found=true
            break
        fi
    done

    if [[ "$config_found" == false ]]; then
        log_error "Configuration file not found in any expected location!"
        log_error "Searched paths: ${config_paths[*]}"
        exit 1
    fi

    # Validate required configuration variables
    validate_config
}

# Validate required configuration parameters
validate_config() {
    local required_vars=("BROKER" "PORT" "USER" "PASS" "HOST_NAME")
    local missing_vars=()

    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required configuration variables: ${missing_vars[*]}"
        exit 1
    fi

    # Validate port number
    if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [[ "$PORT" -lt 1 || "$PORT" -gt 65535 ]]; then
        log_error "Invalid port number: $PORT (must be 1-65535)"
        exit 1
    fi

    # Set default values for optional parameters
    MQTT_QOS="${MQTT_QOS:-1}"
    CSV_RETENTION_DAYS="${CSV_RETENTION_DAYS:-30}"
}

# Load configuration
load_config

# ==============================================================================
# MQTT TOPICS CONFIGURATION
# ==============================================================================

BASE_TOPIC="proxmox/${HOST_NAME}"
TEMP_TOPIC="$BASE_TOPIC/temp"
WEAR_TOPIC="$BASE_TOPIC/wear"
HEALTH_TOPIC="$BASE_TOPIC/health"
ZFS_TOPIC="$BASE_TOPIC/zfs"
AVAIL_TOPIC="$BASE_TOPIC/availability"
DISK_TOPIC="$BASE_TOPIC/disks"
HA_DISCOVERY_PREFIX="${HA_BASE_TOPIC:-homeassistant}"

# ==============================================================================
# MQTT PUBLISHING FUNCTIONS
# ==============================================================================

# Publish MQTT message with retain flag (for persistent data)
# Usage: mqtt_publish_retain "topic" "payload"
mqtt_publish_retain() {
    local topic="$1"
    local payload="$2"

    if [[ -z "$topic" ]]; then
        log_error "MQTT topic is empty"
        return 1
    fi

    if [[ -z "$payload" ]]; then
        log_warn "MQTT payload is empty for topic: $topic"
        return 1
    fi

    if [[ "${DEBUG:-false}" == "true" ]]; then
        log_debug "Would publish (RETAIN) to $topic -> ${payload:0:100}..."
        return 0
    fi

    if mosquitto_pub -h "$BROKER" -p "$PORT" \
                     -u "$USER" -P "$PASS" \
                     -t "$topic" -m "$payload" -r -q "$MQTT_QOS" 2>/dev/null; then
        log_debug "Published (Retain) to $topic"
        return 0
    else
        log_error "Failed to publish to $topic"
        return 1
    fi
}

# Publish MQTT message without retain flag (for transient data)
# Usage: mqtt_publish_no_retain "topic" "payload"
mqtt_publish_no_retain() {
    local topic="$1"
    local payload="$2"

    if [[ -z "$topic" ]]; then
        log_error "MQTT topic is empty"
        return 1
    fi

    if [[ -z "$payload" ]]; then
        log_warn "MQTT payload is empty for topic: $topic"
        return 1
    fi

    if [[ "${DEBUG:-false}" == "true" ]]; then
        log_debug "Would publish (NO-RETAIN) to $topic -> ${payload:0:100}..."
        return 0
    fi

    if mosquitto_pub -h "$BROKER" -p "$PORT" \
                     -u "$USER" -P "$PASS" \
                     -t "$topic" -m "$payload" \
                     --will-topic "$AVAIL_TOPIC" \
                     --will-payload "offline" \
                     --will-retain \
                     -q "$MQTT_QOS" 2>/dev/null; then
        log_debug "Published (No-Retain) to $topic"
        return 0
    else
        log_error "Failed to publish to $topic"
        return 1
    fi
}

# ==============================================================================
# CSV EXPORT FUNCTIONS
# ==============================================================================

# Clean old CSV backup files
# Usage: cleanup_csv_backups (uses CSV_RETENTION_DAYS from config)
cleanup_csv_backups() {
    [[ -z "${OUTPUT_CSV_DIR:-}" ]] && return 0
    [[ ! -d "$OUTPUT_CSV_DIR" ]] && return 0

    local retention_days="${CSV_RETENTION_DAYS:-30}"
    
    log_debug "Cleaning CSV backups older than $retention_days days in $OUTPUT_CSV_DIR..."

    local count=0
    while IFS= read -r -d '' file; do
        rm -f "$file" 2>/dev/null && ((count++))
    done < <(find "$OUTPUT_CSV_DIR" -name "*.csv.bak" -type f -mtime "+$retention_days" -print0 2>/dev/null)

    if [[ $count -gt 0 ]]; then
        log_debug "Cleaned up $count old CSV backup file(s)"
    fi
}

# Write CSV file with automatic backup and cleanup
# Usage: write_csv "filename.csv" "content"
# - Creates OUTPUT_CSV_DIR if necessary
# - Backs up existing file to filename.csv.bak
# - Automatically cleans old backups based on CSV_RETENTION_DAYS
# - Skips if OUTPUT_CSV_DIR is not defined or content is empty
write_csv() {
    local csv_file="$1"
    local csv_content="$2"

    # Skip if CSV export is disabled
    if [[ -z "${OUTPUT_CSV_DIR:-}" ]]; then
        log_debug "CSV export disabled (OUTPUT_CSV_DIR not set)"
        return 0
    fi

    # Skip if content is empty
    if [[ -z "$csv_content" ]]; then
        log_debug "CSV content is empty, skipping file '$csv_file'"
        return 0
    fi

    # Validate filename
    if [[ ! "$csv_file" =~ ^[a-zA-Z0-9._-]+\.csv$ ]]; then
        log_error "Invalid CSV filename: $csv_file (must end with .csv)"
        return 1
    fi

    # Create output directory if it doesn't exist
    if [[ ! -d "$OUTPUT_CSV_DIR" ]]; then
        if mkdir -p "$OUTPUT_CSV_DIR" 2>/dev/null; then
            log_info "Created CSV export directory: $OUTPUT_CSV_DIR"
        else
            log_error "Failed to create CSV export directory: $OUTPUT_CSV_DIR"
            return 1
        fi
    fi

    local full_path="$OUTPUT_CSV_DIR/$csv_file"

    # Backup existing file
    if [[ -f "$full_path" ]]; then
        local backup_path="$full_path.bak"
        if mv "$full_path" "$backup_path" 2>/dev/null; then
            log_debug "Existing CSV backed up to '$backup_path'"
        else
            log_warn "Failed to backup existing CSV: $full_path"
        fi
    fi

    # Write new CSV file
    if printf '%s\n' "$csv_content" > "$full_path" 2>/dev/null; then
        log_debug "CSV file created: '$full_path' ($(wc -l < "$full_path") lines)"
        
        # Automatically cleanup old backups after successful write
        cleanup_csv_backups
        
        return 0
    else
        log_error "Failed to write CSV file: $full_path"
        return 1
    fi
}

# ==============================================================================
# UTILITY FUNCTIONS
# ==============================================================================

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check required dependencies
check_dependencies() {
    local required_commands=("mosquitto_pub")
    local missing_commands=()

    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            missing_commands+=("$cmd")
        fi
    done

    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing_commands[*]}"
        log_error "Install with: apt-get install mosquitto-clients"
        exit 1
    fi
}

# ==============================================================================
# DISPLAY CONFIGURATION - BOX DRAWING FUNCTIONS
# ==============================================================================

# Begin a box section with a title
# Usage: box_begin "Title" [width]
box_begin() {
    local title="$1"
    local width="${2:-64}"
    local title_len=${#title}
    local dash_count=$((width - title_len - 4))
    
    printf "┌─ %s " "$title"
    printf '─%.0s' $(seq 1 $dash_count)
    printf "┐\n"
}

# Format a line inside a box with automatic padding
# Usage: box_line "Label:" "Value" [width]
box_line() {
    local label="$1"
    local value="$2"
    local width="${3:-64}"
    local content="$label $value"
    local content_len=${#content}
    local padding=$((width - content_len - 2))
    
    # Ensure minimum padding
    [[ $padding -lt 0 ]] && padding=0
    
    printf "│ %s%*s│\n" "$content" $padding ""
}

# End a box section
# Usage: box_end [width]
box_end() {
    local width="${1:-64}"
    local padding=$((width - 1))
    printf "└"
    printf '─%.0s' $(seq 1 $padding)
    printf "┘\n"
}

# Display loaded configuration when run directly
display_config() {

    cat <<'EOF'
╔═══════════════════════════════════════════════════════════════╗
║          SentryLab-PVE Configuration                          ║
╚═══════════════════════════════════════════════════════════════╝

EOF

    box_begin "MQTT Connection"
    box_line "Broker:" "$BROKER:$PORT"
    box_line "User:" "$USER"
    box_line "QoS Level:" "$MQTT_QOS"
    box_line "Debug Mode:" "${DEBUG:-false}"
    box_end
    echo

    box_begin "Host Information"
    box_line "Hostname:" "$HOST_NAME"
    box_line "Base Topic:" "$BASE_TOPIC"
    box_line "HA Discovery:" "$HA_DISCOVERY_PREFIX"
    box_end
    echo

    box_begin "CSV Export"
    box_line "Directory:" "${OUTPUT_CSV_DIR:-[not configured]}"
    box_line "Retention:" "${CSV_RETENTION_DAYS:-30} days"
    if [[ -n "${OUTPUT_CSV_DIR:-}" && -d "$OUTPUT_CSV_DIR" ]]; then
        box_line "Status:" "Directory exists"
    else
        box_line "Status:" "Disabled or directory missing"
    fi
    box_end
    echo

    box_begin "Monitoring Features"
    box_line "ZFS Datasets:" "${PUSH_ZFS:-false}"
    box_line "Temperature:" "${PUSH_TEMP:-false}"
    box_line "NVMe Wear:" "${PUSH_NVME_WEAR:-false}"
    box_line "NVMe Health:" "${PUSH_NVME_HEALTH:-false}"
    box_line "Non-ZFS Disks:" "${PUSH_NON_ZFS:-false}"
    box_end
    echo

    box_begin "Configuration File"
    box_line "Path:" "$CONFIG_PATH"
    box_end
}

# ==============================================================================
# INITIALIZATION
# ==============================================================================

# Display configuration when run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
# Check dependencies on load
    check_dependencies
    display_config
fi