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
        box_line "Would publish (RETAIN)"
        box_value "Topic" "$topic"
        box_value "Payload" "${payload}"
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
        box_line "Would publish (NO-RETAIN)"
        box_value "Topic" "$topic"
        box_value "Payload" "${payload}"
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

# Supprime les codes ANSI (codes couleur)
strip_ansi() {
    local s="$1"
    # Remove ANSI escape sequences (color codes) using pure Bash (no external tools)
    # Matches CSI sequences starting with ESC '[' followed by digits/semicolons and a final letter
    local regex=$'\033\[[0-9;]*[ -/]*[@-~]'
    # Iteratively remove all matches using BASH_REMATCH
    while [[ $s =~ $regex ]]; do
        local match="${BASH_REMATCH[0]}"
        s="${s//$match/}"
    done
    printf '%s' "$s"
}


# Begin a box section with a title (Visible only in DEBUG mode)
# Usage: box_begin "Title" [width]
box_begin() {
    [[ "${DEBUG:-false}" != "true" ]] && return 0
    local raw_title="${1:-}"
    local width="${2:-$BOX_WIDTH}"
    # Calculate length based on stripped text to ignore ANSI codes
    local plain_title=$(strip_ansi "$raw_title")
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

# Retourne la largeur affichée réelle (Unicode-safe)
str_width() {
    local s="$1"
    # Remove ANSI and measure character length using current UTF-8 locale
    s=$(strip_ansi "$s")
    echo "${#s}"
}

wrap_text() {
    local text="$1"
    local max="$2"
    [[ -z "$max" || "$max" -le 0 ]] && max=80
    
    # Cas chaîne vide
    [[ -z "$text" ]] && { echo ""; return 0; }
    
    local out=""
    
    # Traiter ligne par ligne (pour respecter les sauts de ligne existants)
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Si on a déjà du contenu, ajouter un saut de ligne
        [[ -n "$out" ]] && out+=$'\n'
        
        # Si la ligne est vide, la conserver
        if [[ -z "$line" ]]; then
            continue
        fi
        
        local cur=""
        local words=()
        
        # Découper en mots (gestion des espaces multiples)
        read -ra words <<< "$line"
        
        for word in "${words[@]}"; do
            [[ -z "$word" ]] && continue
            
            local word_len=$(str_width "$word")
            
            # Si le mot seul est trop long, il faut le couper
            if ((word_len > max)); then
                # Vider la ligne courante d'abord
                if [[ -n "$cur" ]]; then
                    out+="$cur"$'\n'
                    cur=""
                fi
                
                # Couper le mot en morceaux de max caractères
                local remaining="$word"
                while [[ -n "$remaining" ]]; do
                    local chunk=""
                    local chunk_w=0
                    local i=0
                    
                    while ((i < ${#remaining} && chunk_w < max)); do
                        local char="${remaining:i:1}"
                        local char_w=$(str_width "$char")
                        if ((chunk_w + char_w <= max)); then
                            chunk+="$char"
                            ((chunk_w += char_w))
                            ((i++))
                        else
                            break
                        fi
                    done
                    
                    if [[ -n "$chunk" ]]; then
                        out+="$chunk"
                        # Ajouter newline seulement s'il reste du texte
                        [[ ${#remaining} -gt $i ]] && out+=$'\n'
                    fi
                    remaining="${remaining:i}"
                done
                continue
            fi
            
            local test_len
            if [[ -n "$cur" ]]; then
                # Test avec espace
                test_len=$(str_width "$cur $word")
            else
                # Premier mot
                test_len=$word_len
            fi
            
            if ((test_len <= max)); then
                # Ça rentre
                if [[ -n "$cur" ]]; then
                    cur+=" $word"
                else
                    cur="$word"
                fi
            else
                # Ça dépasse : valider la ligne courante
                if [[ -n "$cur" ]]; then
                    out+="$cur"$'\n'
                fi
                cur="$word"
            fi
        done
        
        # Ajouter le reste
        [[ -n "$cur" ]] && out+="$cur"
    done <<< "$text"
    
    printf '%s' "$out"
}

# Convert color name to ANSI code
# Usage: color=$(get_color_code "RED") 
# Supported: RED, GREEN, YELLOW, BLUE, MAGENTA, CYAN, WHITE
get_color_code() {
    local color_name="${1:-CYAN}"
    case "${color_name^^}" in
        RED)    echo $'\033[31m' ;;
        GREEN)  echo $'\033[32m' ;;
        YELLOW) echo $'\033[33m' ;;
        BLUE)   echo $'\033[34m' ;;
        MAGENTA) echo $'\033[35m' ;;
        CYAN)   echo $'\033[36m' ;;
        WHITE)  echo $'\033[37m' ;;
        LIGHTGRAY|LIGHT_GREY|GRAY|GREY|LIGHT_GRAY|LIGHT_GREY) echo $'\033[90m' ;;
        NONE|OFF|NO|DISABLE) echo '' ;;
        *)      echo '' ;;  # Default: no color
    esac
}

# Pad text to a target display width (uses str_width for UTF-8)
pad_to_width() {
    local text="${1-}"
    local target="${2-0}"
    local width
    width=$(str_width "$text")
    local out="$text"
    while (( width < target )); do
        out+=" "
        ((width++))
    done
    printf '%s' "$out"
}

# Print a label:value pair. The label is kept on the first line and the value is colored.
# The value may wrap across multiple lines; wrapped lines start aligned at the value column
# Usage: box_value "Label" "Some potentially long value" [width]
box_value() {
    [[ "${DEBUG:-false}" != "true" ]] && return 0

    local label="${1-}"
    local value="${2-}"
    local width="${3-$BOX_WIDTH}"
    [[ ! "$width" =~ ^[0-9]+$ ]] && width=$BOX_WIDTH
    local inner=$((width - 4))

    # Colors
    local RED=$'\033[31m'
    local GRN=$'\033[32m'
    local YEL=$'\033[33m'
    local CYA=$'\033[36m'
    local CLR=$'\033[0m'

    # prepare label with colon and space
    local label_txt="${label}: "
    local label_w=$(str_width "$label_txt")
    # ensure label fits in a single line; truncate if necessary
    if (( label_w >= inner )); then
        # truncate to leave at least 1 char for value column
        local max_label=$((inner - 2))
        label_txt="${label_txt:0:$max_label}… "
        label_w=$(str_width "$label_txt")
    fi

    # Decide color for the value based on content
    local color=$CYA
    if [[ "$value" == ERROR* || "$value" == false ]]; then
        color=$RED
    elif [[ "$value" == INFO* || "$value" == true || "$value" == "Directory exists" ]]; then
        color=$GRN
    elif [[ "$value" == SKIP* || "$value" == *Disabled* ]]; then
        color=$YEL
    fi

    # Wrap the value to the available width
    local avail=$((inner - label_w))
    (( avail < 1 )) && avail=1
    local wrapped_value
    wrapped_value=$(wrap_text "$value" "$avail")

    # Render first line: label + colored first chunk
    local first=true
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$first" == true ]]; then
            # pad line to available width (UTF-8 aware), then apply color/reset
            local padded_line
            padded_line=$(pad_to_width "$line" "$avail")
            printf "│ %s%b%s%b │\n" "$label_txt" "$color" "$padded_line" "$CLR"
            first=false
        else
            # subsequent lines: indent to value column, pad (UTF-8 aware), then color/reset
            local indent=""
            # create spaces equal to label width
            for ((i=0;i<label_w;i++)); do indent+=" "; done
            local padded_line
            padded_line=$(pad_to_width "$line" "$avail")
            printf "│ %s%b%s%b │\n" "$indent" "$color" "$padded_line" "$CLR"
        fi
    done <<< "$wrapped_value"
}


# Print arbitrary text lines inside the box. Uses a single color chosen from keywords or explicit.
# Usage: box_line "Some text" [width] [color_name]
# Color names: RED, GREEN, YELLOW, BLUE, MAGENTA, CYAN, WHITE
# If no color specified, auto-detects based on keywords (ERROR, INFO, SKIP, etc.)
box_line() {
    [[ "${DEBUG:-false}" != "true" ]] && return 0
    local input="${1-}"
    local width="${2-$BOX_WIDTH}"
    local color_override="${3-}"
    # If width is non-numeric, treat it as a color override for convenience
    if [[ ! "$width" =~ ^[0-9]+$ ]]; then
        if [[ -z "$color_override" && -n "$width" ]]; then
            color_override="$width"
        fi
        width=$BOX_WIDTH
    fi
    local inner=$((width - 4))

    # Colors
    local RED=$'\033[31m'
    local GRN=$'\033[32m'
    local YEL=$'\033[33m'
    local CLR=$'\033[0m'

    # choose a single color for the whole input
    local color=""
    local lower="${input,,}"

    # If explicit color provided, use it (supports NONE for no color)
    if [[ -n "$color_override" ]]; then
        color=$(get_color_code "$color_override")
    else
        # Otherwise, auto-detect based on keywords
        if [[ "$input" == ERROR* || "$input" == *ERROR* ]]; then
            color="$RED"
        elif [[ "$input" == INFO* || "$input" == *INFO* ]]; then
            color="$GRN"
        elif [[ "$input" == SKIP* || "$input" == *Disabled* || "$lower" == *disabled* || "$lower" == skipped* || "$lower" == *skipped* ]]; then
            color=$(get_color_code "LIGHTGRAY")
        elif [[ "$input" == WARNING* || "$input" == *WARNING* ]]; then
            color="$YEL"
        else
            color=$(get_color_code "WHITE")  # default: white for maximum compatibility
        fi
    fi

    if [[ -z "$input" ]]; then
        printf "│ %*s │\n" "$inner" ""
        return
    fi

    local wrapped
    wrapped=$(wrap_text "$input" "$inner")
    while IFS= read -r line || [[ -n "$line" ]]; do
        local padded_line
        padded_line=$(pad_to_width "$line" "$inner")
        if [[ -n "$color" ]]; then
            printf "│ %b%s%b │\n" "$color" "$padded_line" "$CLR"
        else
            printf "│ %s │\n" "$padded_line"
        fi
    done <<< "$wrapped"
}

# End a box section
# Usage: box_end [wiydth]
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
    local color=""
    box_title "SentryLab-PVE Configuration" 

    box_begin "MQTT Connection"
    box_value "Broker" "${BROKER}:${PORT}"
    box_value "User" "${USER:-[none]}"
    box_value "QoS Level" "${MQTT_QOS:-0}"
    box_value "Debug Mode" "${DEBUG:-false}"
    box_end
    echo

    box_begin "Host Information"
    box_value "Hostname" "$HOST_NAME"
    box_value "Base Topic" "$BASE_TOPIC"
    box_value "HA Discovery" "$HA_DISCOVERY_PREFIX"
    box_end
    echo

    box_begin "CSV Export"
    box_value "Directory" "${OUTPUT_CSV_DIR:-[not configured]}"
    box_value "Retention" "${CSV_RETENTION_DAYS:-30} days"
    if [[ -n "${OUTPUT_CSV_DIR:-}" && -d "$OUTPUT_CSV_DIR" ]]; then
        box_value "Status" "Directory exists"
    else
        box_value "Status" "ERROR: Disabled or directory missing"
    fi
    box_end

    box_begin "Monitoring Features"
    box_value "System Monitoring" "${PUSH_SYSTEM:-false}"
    box_value "NVMe Temperature" "${PUSH_NVME_TEMP:-false}"
    box_value "NVMe Wear" "${PUSH_NVME_WEAR:-false}"
    box_value "NVMe Health" "${PUSH_NVME_HEALTH:-false}"
    box_value "ZFS Datasets" "${PUSH_ZFS:-false}"
    box_value "Non-ZFS Disks" "${PUSH_NON_ZFS:-false}"
    box_end
    echo

    box_begin "Dependencies"
    box_value "Dependencies" "$(check_dependencies false)"
    box_end

    box_begin "Configuration File"
    box_value "Path" "$CONFIG_PATH"
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
