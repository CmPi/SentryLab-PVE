#!/bin/bash

#
# @file /usr/local/bin/sentrylab/passive.sh
# @author CmPi <cmpi@webe.fr>
# @brief Orchestrator for passive monitoring (no disk wake)
# @date 2025-12-28
# @version 1.1.361
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

log_info "=== PASSIVE MONITORING CYCLE START ==="

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

# --- NVMe Wear Monitoring ---
if [[ "${PUSH_NVME_WEAR:-false}" == "true" ]]; then
    log_debug "Running NVMe wear collection..."
    if "$SCRIPT_DIR/wear.sh"; then
        log_debug "✓ NVMe wear collected"
        MONITORING_ENABLED=true
    else
        log_error "✗ NVMe wear collection failed"
    fi
else
    log_debug "NVMe wear monitoring disabled (PUSH_NVME_WEAR=false)"
fi

# --- NVMe Health Monitoring ---
if [[ "${PUSH_NVME_HEALTH:-false}" == "true" ]]; then
    log_debug "Running NVMe health collection..."
    if "$SCRIPT_DIR/health.sh"; then
        log_debug "✓ NVMe health collected"
        MONITORING_ENABLED=true
    else
        log_error "✗ NVMe health collection failed"
    fi
else
    log_debug "NVMe health monitoring disabled (PUSH_NVME_HEALTH=false)"
fi

# --- Warning if nothing is enabled ---
if [[ "$MONITORING_ENABLED" == "false" ]]; then
    log_warn "No passive monitoring enabled in sentrylab.conf"
    log_warn "Enable at least one of: PUSH_SYSTEM, PUSH_NVME_TEMP, PUSH_NVME_WEAR, PUSH_NVME_HEALTH"
fi

log_info "=== PASSIVE MONITORING CYCLE COMPLETE ==="

exit 0