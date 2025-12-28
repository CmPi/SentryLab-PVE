#!/bin/bash

#
# @file /usr/local/bin/sentrylab/active.sh
# @author CmPi <cmpi@webe.fr>
# @brief Orchestrator for active monitoring (may wake disks)
# @date 2025-12-28
# @version 1.2.0
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

log_info "=== ACTIVE MONITORING CYCLE START ==="

# Track if any monitoring is enabled
MONITORING_ENABLED=false

# Optional: Check if disks are already awake (uncomment to enable)
# if ! are_disks_awake; then
#     log_info "Disks are sleeping, skipping active monitoring to preserve power"
#     exit 0
# fi

# --- ZFS Pool Monitoring ---
if [[ "${PUSH_ZFS:-false}" == "true" ]]; then
    log_debug "Running ZFS metrics collection..."
    if "$SCRIPT_DIR/zfs.sh"; then
        log_debug "✓ ZFS metrics collected"
        MONITORING_ENABLED=true
    else
        log_error "✗ ZFS metrics collection failed"
    fi
else
    log_debug "ZFS monitoring disabled (PUSH_ZFS=false)"
fi

# --- Non-ZFS Disk Monitoring ---
if [[ "${PUSH_NON_ZFS:-false}" == "true" ]]; then
    log_debug "Running non-ZFS disk collection..."
    if [[ -f "$SCRIPT_DIR/non-zfs.sh" ]]; then
        if "$SCRIPT_DIR/non-zfs.sh"; then
            log_debug "✓ Non-ZFS disk metrics collected"
            MONITORING_ENABLED=true
        else
            log_error "✗ Non-ZFS disk collection failed"
        fi
    else
        log_warn "non-zfs.sh not found, skipping"
    fi
else
    log_debug "Non-ZFS disk monitoring disabled (PUSH_NON_ZFS=false)"
fi

# --- Warning if nothing is enabled ---
if [[ "$MONITORING_ENABLED" == "false" ]]; then
    log_warn "No active monitoring enabled in sentrylab.conf"
    log_warn "Enable at least one of: PUSH_ZFS, PUSH_NON_ZFS"
fi

log_info "=== ACTIVE MONITORING CYCLE COMPLETE ==="

exit 0