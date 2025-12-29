#!/bin/bash
#
# @file /usr/local/bin/sentrylab/non-zfs.sh
# @author CmPi <cmpi@webe.fr>
# @brief Collects status of non-pool drives
# @date 2025-12-26
# @version 1.0.359.5
# @usage Run periodically (e.g., every hour via cron or systemd timer)
# @notes make it executable as usual
#        chmod +x /usr/local/bin/*.sh
#        WARNING: This script uses smartctl which WAKES sleeping drives
#

set -euo pipefail