#!/bin/bash

#
# @file /usr/local/bin/sentrylab/temp.sh
# @author CmPi <cmpi@webe.fr>
# @brief Releve les températures CPU, NVMe et NAS ambient et les publie via MQTT
# @date 2025-12-27
# @version 1.1.361
# @usage À exécuter périodiquement (ex: via cron ou timer systemd)
# @notes * make it executable as usual using the command:
#          chmod +x /usr/local/bin/*.sh
#        * set DEBUG to true in config.conf and run it in simulation mode
#        * box_begin, box_line, box_value and box_end functions do nothing when DEBUG is false 

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

# --- Initialisation JSON ---
JSON=$(jq -n '{}')

box_begin "System metrics collection"

if [[ "$PUSH_SYSTEM" == "true" ]]; then
    box_line "INFO: System metrics publishing is enabled (PUSH_SYSTEM == true)"    

else
    box_line "SKIPPED: System metrics publishing is disabled (PUSH_SYSTEM != true)"    
fi

box_end
