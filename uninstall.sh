#!/bin/bash
#
# @file install.sh
# @author CmPi <cmpi@webe.fr>
# @repo https://github.com/CmPi/SentryLab-PVE
# @brief Root installation script for SentryLab-PVE
# @date 2025-12-28
# @version 1.1.361
# @usage sudo ./install.sh
#

set -euo pipefail

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi


CONF_FILE="/usr/local/etc/sentrylab.conf"
DEST_DIR="/usr/local/bin/sentrylab"
AUTO_DIR="/etc/systemd/system"
EXPORT_DIR="/var/lib/sentrylab/csv"

echo "--- SentryLab Uninstallation ---"

