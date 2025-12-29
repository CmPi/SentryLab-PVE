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
SYSTEM_TOPIC="$BASE_TOPIC/system"
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
        box_line "Would publish (RETAIN) to $topic"
        box_line "Payload: ${payload:0:100}"
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
    local retention_days="${CSV_RETENTION_DAYS:-30}"
    [[ "$retention_days" =~ ^[0-9]+$ ]] || retention_days=30
    [[ -z "${OUTPUT_CSV_DIR:-}" || ! -d "$OUTPUT_CSV_DIR" ]] && return 0
    find "$OUTPUT_CSV_DIR" -type f -name "*.bak" -mtime +"$retention_days" \
        -exec rm -f {} \; 2>/dev/null || true
}




# Write CSV and return status message
# Usage: result=$(write_csv "file.csv" "Header" "Data")
# Write CSV with backup, cleanup and selective writing
# Returns a status message for box_line
write_csv() {
local csv_file="${1:-}"
    local header="${2:-}"  # Header
    local data="${3:-}"    # Data
    local csv_content=""
    local warn=""

    if [[ -z "${OUTPUT_CSV_DIR:-}" ]]; then
        echo "SKIP: CSV export disabled in sentrylab.conf"
        return 1
    fi    

    if [[ -z "$header" && -z "$data" ]]; then
        echo "SKIP: CSV file creation disabled for this set of metrics"
        return 0
    fi

    # 2. CAS : Header présent mais Data vide (Scan effectué, rien trouvé)
    if [[ -n "$header" && -z "$data" ]]; then
        csv_content=$(echo -e "$header" | sed 's/\n$//')
        local status_msg="INFO: Only Header (No data)"
    else
        # 3. CAS : Header + Data (Normal)
        # Validation des colonnes
        local c_hdr=$(echo -e "$header" | head -n 1 | awk -F',' '{print NF}')
        local c_dat=$(echo -e "$data" | sed '/^$/d' | head -n 1 | awk -F',' '{print NF}')
        [[ "$c_hdr" -ne "$c_dat" ]] && warn=" (Mismatch: $c_hdr/$c_dat cols)"

        csv_content=$(printf "%s\n%s" "$(echo -e "$header" | sed 's/\n$//')" "$(echo -e "$data" | sed '/^$/d')")
        local lines=$(echo "$csv_content" | wc -l)
        local status_msg="INFO: $lines lines$warn"
    fi

    # --- Procédure d'écriture ---
    [[ -z "${OUTPUT_CSV_DIR:-}" ]] && { echo "SKIP: No dir"; return 0; }

    if [[ ! -d "$OUTPUT_CSV_DIR" ]]; then
        if ! mkdir -p "$OUTPUT_CSV_DIR" 2>/dev/null; then
            echo "ERROR: Cannot create directory"
            return 1
        fi
    fi

    local full_path="$OUTPUT_CSV_DIR/$csv_file"
    [[ -f "$full_path" ]] && mv "$full_path" "$full_path.bak" 2>/dev/null

    if printf '%s\n' "$csv_content" > "$full_path" 2>/dev/null; then
        cleanup_csv_backups >/dev/null 2>&1
        echo "$status_msg"
        return 0
    else
        echo "ERROR: Write failed"
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
    local exit_if_missing="${1:-true}"

    local required_commands=("mosquitto_pub" "jq")

    [[ "${PUSH_ZFS:-false}" == "true" ]] && required_commands+=("zpool")
    [[ "${PUSH_NON_ZFS:-false}" == "true" ]] && required_commands+=("df")
#   [[ "${PUSH_NVME_TEMP:-false}" == "true" || "${PUSH_NVME_WEAR:-false}" == "true" || "${PUSH_NVME_HEALTH:-false}" == "true" ]] && required_commands+=("nvme")
        
    local missing_commands=()

    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            missing_commands+=("$cmd")
        fi
    done

    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        if [[ "$exit_if_missing" == "true" ]]; then
            log_error "Missing required commands: ${missing_commands[*]}"
            log_error "Install with: apt-get install mosquitto-clients"
            exit 1
        else
            echo "ERROR: Missing commands: ${missing_commands[*]}"
            return 1
        fi
    else
        if [[ "$exit_if_missing" == "false" ]]; then
            echo "INFO: All required commands are available"
            return 0    
        fi
    fi
}

# ==============================================================================
# DISPLAY CONFIGURATION - BOX DRAWING FUNCTIONS
# ==============================================================================

BOX_WIDTH=80

strip_colors() {
    local text="${1:-}"
    [[ -z "$text" ]] && return 0
    local clean="${text//[$'\e']\[[0-9;]*m/}"
    printf '%s' "$clean"
}


strip_ansi() {
    local s="$1"
    while [[ "$s" =~ $'\e''\[[0-9;]*m' ]]; do
        s="${s/${BASH_REMATCH[0]}/}"
    done
    printf '%s' "$s"
}


# Titre Majeur (Bordure double, centré)
box_title() {
    [[ "${DEBUG:-false}" != "true" ]] && return 0
    local title="$1"
    local width="${2:-80}"
    local inner=$((width - 2))
    [ ${#title} -gt $inner ] && title="${title:0:$((inner - 3))}..."
    local t_len=${#title}
    local l_pad=$(( (inner - t_len) / 2 ))
    local r_pad=$(( inner - t_len - l_pad ))
    printf "╔"; printf '═%.0s' $(seq 1 $inner); printf "╗\n"
    printf "║%*s%s%*s║\n" "$l_pad" "" "$title" "$r_pad" ""
    printf "╚"; printf '═%.0s' $(seq 1 $inner); printf "╝\n"
}

# Begin a box section with a title (Visible only in DEBUG mode)
# Usage: box_begin "Title" [width]
box_begin() {
    [[ "${DEBUG:-false}" != "true" ]] && return 0
    local raw_title="${1:-}"
    local width="${2:-$BOX_WIDTH}"
    # Calculate length based on stripped text to ignore ANSI codes
    local plain_title=$(strip_colors "$raw_title")
    local title_len=${#plain_title}
    # 1. Handle Empty Title
    if [[ -z "$plain_title" ]]; then
        local dash_count=$((width - 2))
        [[ $dash_count -lt 0 ]] && dash_count=0
        printf "┌"
        printf '─%.0s' $(seq 1 $dash_count)
        printf "┐\n"
        return 0
    fi
    # 2. Handle Title Too Long (Truncate if necessary)
    # Max title length = width - 6 (corners: 2, padding: 2, dashes: 2)
    local max_title_len=$((width - 6))
    if [[ $title_len -gt $max_title_len ]]; then
        # Truncate the original (potentially colored) title
        # We use the plain length to determine where to cut
        raw_title="${raw_title:0:$max_title_len}…"
        title_len=$((max_title_len + 1))
    fi
    # 3. Calculate Dashes and Print
    local dash_count=$((width - title_len - 5))
    [[ $dash_count -lt 0 ]] && dash_count=0
    printf "┌─ %b " "$raw_title"
    printf '─%.0s' $(seq 1 $dash_count)
    printf "┐\n"
}

# retourne la largeur affichée réelle (Unicode-safe)
str_width() {
    local s="$1"
    local w=0 c
    while IFS= read -r -n1 c; do
        [[ -z "$c" ]] && continue
        LC_ALL=C printf '%s' "$c" | grep -q '[ -~]' && ((w++)) || ((w+=2))
    done <<< "$s"
    echo "$w"
}

wrap_text() {
    local text="${1-}"
    local max="${2-0}"
    local cur="" word out=""
    # Cas chaîne vide → une ligne vide
    [[ -z "$text" ]] && { printf '\n'; return 0; }
    for word in $text; do
        local test
        if [[ -n "$cur" ]]; then
            test="$cur $word"
        else
            test="$word"
        fi
        if (( $(str_width "$test") <= max )); then
            cur="$test"
        else
            out+="$cur"$'\n'
            cur="$word"
        fi
    done
    out+="$cur"
    printf '%s' "$out"
}


box_line() {
    [[ "${DEBUG:-false}" != "true" ]] && return 0

    local input="${1-}"
    local width="${2-$BOX_WIDTH}"
    [[ ! "$width" =~ ^[0-9]+$ ]] && width=80
    local max=$((width - 4))

    # Colors
    local RED='\033[31m'
    local GRN='\033[32m'
    local YEL='\033[33m'
    local CYA='\033[36m'
    local CLR='\033[0m'

    local raw phys_line colored plain wrapped vis pad

    # Si input vide → forcer une ligne vide
    [[ -z "$input" ]] && input=""

    while IFS= read -r raw || [[ -z "$raw" ]]; do

        # ---- coloration ----
        if [[ "$raw" == *": "* ]]; then
            local label="${raw%%: *}: "
            local value="${raw#*: }"

            if [[ "$value" == ERROR* || "$value" == false ]]; then
                value="${RED}${value}${CLR}"
            elif [[ "$value" == INFO* || "$value" == true || "$value" == "Directory exists" ]]; then
                value="${GRN}${value}${CLR}"
            elif [[ "$value" == SKIP* || "$value" == *Disabled* ]]; then
                value="${YEL}${value}${CLR}"
            else
                value="${CYA}${value}${CLR}"
            fi
            colored="${label}${value}"
        else
            colored="$raw"
            [[ "$colored" == ERROR* ]] && colored="${RED}${colored}${CLR}"
            [[ "$colored" == INFO*  ]] && colored="${GRN}${colored}${CLR}"
        fi

        plain=$(strip_ansi "$colored")
        wrapped=$(wrap_text "$plain" "$max")

        # ---- rendu ----
        while IFS= read -r phys_line || [[ -z "$phys_line" ]]; do
            vis=$(str_width "$phys_line")
            pad=$((max - vis))
            printf "│ %b%*s │\n" \
                "${colored%%"$plain"*}$phys_line${colored#"$plain"}" \
                "$pad" ""
        done <<< "$wrapped"

    done <<< "$input"
}



# End a box section
# Usage: box_end [width]
box_end() {
    [[ "${DEBUG:-false}" != "true" ]] && return 0
    local width="${1:-$BOX_WIDTH}"
    local dash_count=$((width - 2))
    [[ $dash_count -lt 0 ]] && dash_count=0
    printf "└"
    if [[ $dash_count -gt 0 ]]; then
        printf '─%.0s' $(seq 1 $dash_count)
    fi
    printf "┘\n"
}

# Display loaded configuration when run directly
display_config() {
    clear

    box_title "SentryLab-PVE Configuration" 

    box_begin "MQTT Connection"
    # Ensure $PORT is treated as part of the value for coloring
    box_line "Broker: ${BROKER}:${PORT}"
    box_line "User: ${USER:-[none]}"
    box_line "QoS Level: ${MQTT_QOS:-0}"
    # Fixed the missing $ before {DEBUG}
    box_line "Debug Mode: ${DEBUG:-false}"
    box_end
    echo

    box_begin "Host Information"
    box_line "Hostname: $HOST_NAME"
    box_line "Base Topic: $BASE_TOPIC"
    box_line "HA Discovery: $HA_DISCOVERY_PREFIX"
    box_end
    echo

    box_begin "CSV Export"
    box_line "Directory: ${OUTPUT_CSV_DIR:-[not configured]}"
    box_line "Retention: ${CSV_RETENTION_DAYS:-30} days"
    # Logic remains the same, box_line will handle the coloring of 'Status'
    if [[ -n "${OUTPUT_CSV_DIR:-}" && -d "$OUTPUT_CSV_DIR" ]]; then
        box_line "Status: Directory exists"
    else
        box_line "Status: ERROR: Disabled or directory missing"
    fi
    box_end
    echo

    box_begin "Monitoring Features"
    box_line "System Monitoring: ${PUSH_SYSTEM:-false}"
    box_line "NVMe Temperature: ${PUSH_NVME_TEMP:-false}"
    box_line "NVMe Wear: ${PUSH_NVME_WEAR:-false}"
    box_line "NVMe Health: ${PUSH_NVME_HEALTH:-false}"
    box_line "ZFS Datasets: ${PUSH_ZFS:-false}"
    box_line "Non-ZFS Disks: ${PUSH_NON_ZFS:-false}"
    box_end
    echo

    box_begin "Dependencies"
    box_line "$(check_dependencies false)"
    box_end

    box_begin "Configuration File"
    box_line "Path: $CONFIG_PATH"
    box_end
}

# ==============================================================================
# INITIALIZATION
# ==============================================================================

# Display configuration when run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
# Check dependencies on load
    display_config
else
    check_dependencies   
fi