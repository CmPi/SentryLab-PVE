#!/bin/bash

#
# @file /usr/local/bin/sentrylab/non-zfs.sh
# @author CmPi <cmpi@webe.fr>
# @brief Collects status of non-pool drives
# @date 2025-12-26
# @version 1.0.359.5
# @usage Run periodically (e.g., every hour via cron or systemd timer)
# @notes * make it executable as usual
#          chmod +x /usr/local/bin/*.sh
#        * set DEBUG to true in config.conf and run it in simulation mode
#        * WARNING: This script uses smartctl which WAKES sleeping drives
#        * box_begin, box_line, box_value and box_end functions do nothing when DEBUG is false
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

box_begin "Non-ZFS Drives metrics Collection"

if [[ "${PUSH_NON_ZFS:-false}" == "true" ]]; then

    box_line "INFO: Non-ZFS drives metrics publishing is enabled (PUSH_NON_ZFS == true)" 

else
    box_line "INFO: Non-ZFS drives metrics publishing is disabled (PUSH_NON_ZFS != true)" 
fi

box_end
