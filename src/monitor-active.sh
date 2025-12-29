#!/bin/bash

#
# @file /usr/local/bin/sentrylab/active.sh
# @author CmPi <cmpi@webe.fr>
# @brief Orchestrator for active monitoring (may wake disks)
# @date 2025-12-29
# @version 1.0.363
# @usage Called by sentrylab-active.timer (evening or opportunistic)
# @notes Respects PUSH_* flags from sentrylab.conf
#        WARNING: This script may wake sleeping disks
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/utils.sh" ]; then
    source "$SCRIPT_DIR/utils.sh"
else
    echo "ERROR: Required file '$SCRIPT_DIR/utils.sh' not found." >&2
    exit 1
fi

box_title "ACTIVE MONITORING CYCLE"

# --- ZFS Pool Monitoring ---
if [[ "${PUSH_ZFS:-false}" == "true" ]]; then
    MONITOR_MODE=active "$SCRIPT_DIR/zfs.sh"
else
    box_begin "ZFS Pool"
    box_line "SKIP: ZFS pool monitoring disabled (PUSH_ZFS=false)"
    box_end
fi

# --- Non-ZFS Disk Monitoring ---
if [[ "${PUSH_NON_ZFS:-false}" == "true" ]]; then
    MONITOR_MODE=active "$SCRIPT_DIR/non-zfs.sh"
else
    box_begin "Non-ZFS Disks"
    box_line "SKIP: Non-ZFS disk monitoring disabled (PUSH_NON_ZFS=false)"
    box_end
fi

# --- NVMe Wear Monitoring ---
if [[ "${PUSH_NVME_WEAR:-false}" == "true" ]]; then
    "$SCRIPT_DIR/wear.sh"
else
    box_begin "NVMe Wear"
    box_line "SKIP: NVMe wear monitoring disabled (PUSH_NVME_WEAR=false)"
    box_end
fi

# --- NVMe Health Monitoring ---
if [[ "${PUSH_NVME_HEALTH:-false}" == "true" ]]; then
    "$SCRIPT_DIR/health.sh"
else
    box_begin "NVMe Health"
    box_line "SKIP: NVMe health monitoring disabled (PUSH_NVME_HEALTH=false)"
    box_end
fi

exit 0