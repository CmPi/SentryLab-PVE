#!/bin/bash

#
# @file /usr/local/bin/sentrylab/active.sh
# @author CmPi <cmpi@webe.fr>
# @brief Orchestrator for active monitoring (may wake disks)
# @date 2025-12-29
# @version 1.2.2
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

box_begin "ACTIVE MONITORING CYCLE"

# Track if any monitoring is enabled
MONITORING_ENABLED=false

# Optional: Check if disks are already awake (uncomment to enable)
# if ! are_disks_awake; then
#     log_info "Disks are sleeping, skipping active monitoring to preserve power"
#     exit 0
# fi

# --- ZFS Pool Monitoring ---
if [[ "${PUSH_ZFS:-false}" == "true" ]]; then
    box_line "Running ZFS metrics collection..."
    if MONITOR_MODE=active "$SCRIPT_DIR/zfs.sh"; then
        box_line "✓ ZFS metrics collected"
        MONITORING_ENABLED=true
    else
        box_line "✗ ZFS metrics collection failed"
    fi
else
    box_line "SKIP: ZFS monitoring disabled (PUSH_ZFS=false)"
fi

# --- Non-ZFS Disk Monitoring ---
if [[ "${PUSH_NON_ZFS:-false}" == "true" ]]; then
    box_line "Running non-ZFS disk collection..."
    if [[ -f "$SCRIPT_DIR/non-zfs.sh" ]]; then
        if MONITOR_MODE=active "$SCRIPT_DIR/non-zfs.sh"; then
            log_debug "✓ Non-ZFS disk metrics collected"
            MONITORING_ENABLED=true
        else
            log_error "✗ Non-ZFS disk collection failed"
        fi
    else
        box_line "SKIP: non-zfs.sh not found, skipping"
    fi
else
    box_line "SKIP: Non-ZFS disk monitoring disabled (PUSH_NON_ZFS=false)"
fi

# --- NVMe Wear Monitoring ---
if [[ "${PUSH_NVME_WEAR:-false}" == "true" ]]; then
    box_line "Running NVMe wear collection..."
    if "$SCRIPT_DIR/wear.sh"; then
        box_line "INFO: ✓ NVMe wear collected"
        MONITORING_ENABLED=true
    else
        box_line "ERROR: ✗ NVMe wear collection failed"
    fi
else
    box_line "SKIP: NVMe wear monitoring disabled (PUSH_NVME_WEAR=false)"
fi

# --- NVMe Health Monitoring ---
if [[ "${PUSH_NVME_HEALTH:-false}" == "true" ]]; then
    box_line "Running NVMe health collection..."
    if "$SCRIPT_DIR/health.sh"; then
        box_line "✓ NVMe health collected"
        MONITORING_ENABLED=true
    else
        box_line "ERROR: ✗ NVMe health collection failed"
    fi
else
    box_line "SKIP: NVMe health monitoring disabled (PUSH_NVME_HEALTH=false)"
fi

# --- Warning if nothing is enabled ---
if [[ "$MONITORING_ENABLED" == "false" ]]; then
    box_line "WARNING: No active monitoring enabled in sentrylab.conf"
    box_line "WARNING: Enable at least one of: PUSH_ZFS, PUSH_NON_ZFS"
fi

box_end

exit 0