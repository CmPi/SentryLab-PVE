#!/bin/bash

#
# @file /usr/local/bin/sentrylab/passive.sh
# @author CmPi <cmpi@webe.fr>
# @brief Orchestrator for passive monitoring (no disk wake)
# @date 2025-12-29
# @version 1.0.363
# @usage Called by sentrylab-passive.timer every 3-5 minutes
# @notes Respects PUSH_* flags from sentrylab.conf
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/utils.sh" ]; then
    source "$SCRIPT_DIR/utils.sh"
else
    echo "ERROR: Required file '$SCRIPT_DIR/utils.sh' not found." >&2
    exit 1
fi

box_title "PASSIVE MONITORING CYCLE"

# --- System Metrics (CPU temp, chassis, load, cores) ---
if [[ "${PUSH_SYSTEM:-false}" == "true" ]]; then
    "$SCRIPT_DIR/system.sh"
else
    box_begin "System Metrics"
    box_line "SKIP: System monitoring disabled (PUSH_SYSTEM=false)"
    box_end
fi

# --- NVMe Temperature Monitoring ---
if [[ "${PUSH_NVME_TEMP:-false}" == "true" ]]; then
    "$SCRIPT_DIR/temp.sh"
else
    box_begin "NVMe Temperature"
    box_line "SKIP: NVMe temperature monitoring disabled (PUSH_NVME_TEMP=false)"
    box_end
fi

# --- ZFS Pool Monitoring (passive: skip sleeping devices) ---
if [[ "${PUSH_ZFS:-false}" == "true" ]]; then
    MONITOR_MODE=passive "$SCRIPT_DIR/zfs.sh"
else
    box_begin "ZFS Pool"
    box_line "SKIP: ZFS pool monitoring disabled (PUSH_ZFS=false)"
    box_end
fi

# --- Non-ZFS Disk Monitoring (passive: skip sleeping devices) ---
if [[ "${PUSH_NON_ZFS:-false}" == "true" ]]; then
    MONITOR_MODE=passive "$SCRIPT_DIR/non-zfs.sh"
else
    box_begin "Non-ZFS Disks"
    box_line "SKIP: Non-ZFS disk monitoring disabled (PUSH_NON_ZFS=false)"
    box_end
fi

exit 0