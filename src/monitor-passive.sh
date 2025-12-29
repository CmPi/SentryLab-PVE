#!/bin/bash

#
# @file /usr/local/bin/sentrylab/passive.sh
# @author CmPi <cmpi@webe.fr>
# @brief Orchestrator for passive monitoring (no disk wake)
# @date 2025-12-29
# @version 1.1.363
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

box_begin "PASSIVE MONITORING CYCLE START"

# Track if any monitoring is enabled
MONITORING_ENABLED=false

# --- System Metrics (CPU temp, chassis, load, cores) ---
if [[ "${PUSH_SYSTEM:-false}" == "true" ]]; then
    log_debug "Running system metrics collection..."
    if "$SCRIPT_DIR/system.sh"; then
        log_debug "✓ System metrics collected"
        MONITORING_ENABLED=true
    else
        log_error "✗ System metrics collection failed"
    fi
else
    log_debug "System monitoring disabled (PUSH_SYSTEM=false)"
fi

# --- NVMe Temperature Monitoring ---
if [[ "${PUSH_NVME_TEMP:-false}" == "true" ]]; then
    log_debug "Running NVMe temperature collection..."
    if "$SCRIPT_DIR/temp.sh"; then
        log_debug "✓ NVMe temperatures collected"
        MONITORING_ENABLED=true
    else
        log_error "✗ NVMe temperature collection failed"
    fi
else
    log_debug "NVMe temperature monitoring disabled (PUSH_NVME_TEMP=false)"
fi

# --- ZFS Pool Monitoring (passive: skip sleeping devices) ---
if [[ "${PUSH_ZFS:-false}" == "true" ]]; then
    log_debug "Running ZFS metrics collection (passive)..."
    if MONITOR_MODE=passive "$SCRIPT_DIR/zfs.sh"; then
        log_debug "✓ ZFS metrics collected (passive)"
        MONITORING_ENABLED=true
    else
        log_error "✗ ZFS metrics collection failed (passive)"
    fi
else
    log_debug "ZFS monitoring disabled (PUSH_ZFS=false)"
fi

# --- Non-ZFS Disk Monitoring (passive: skip sleeping devices) ---
if [[ "${PUSH_NON_ZFS:-false}" == "true" ]]; then
    log_debug "Running non-ZFS disk collection (passive)..."
    if [[ -f "$SCRIPT_DIR/non-zfs.sh" ]]; then
        if MONITOR_MODE=passive "$SCRIPT_DIR/non-zfs.sh"; then
            log_debug "✓ Non-ZFS disk metrics collected (passive)"
            MONITORING_ENABLED=true
        else
            log_error "✗ Non-ZFS disk collection failed (passive)"
        fi
    else
        log_warn "non-zfs.sh not found, skipping"
    fi
else
    log_debug "Non-ZFS disk monitoring disabled (PUSH_NON_ZFS=false)"
fi

# --- Warning if nothing is enabled ---
if [[ "$MONITORING_ENABLED" == "false" ]]; then
    log_warn "No passive monitoring enabled in sentrylab.conf"
    log_warn "Enable at least one of: PUSH_SYSTEM, PUSH_NVME_TEMP, PUSH_ZFS, PUSH_NON_ZFS"
fi

box_end

exit 0