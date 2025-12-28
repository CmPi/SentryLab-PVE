#!/bin/bash
#
# @file /usr/local/bin/sentrylab/non-zfs.sh
# @author CmPi <cmpi@webe.fr>
# @brief Relève le statut des disques hors pool
# @date 2025-12-26
# @version 1.0.359.5
# @usage À exécuter périodiquement (ex: toutes les heures via cron ou timer systemd)
# @notes make it executable as usual
#        chmod +x /usr/local/bin/*.sh
#        ATTENTION: Ce script utilise smartctl qui RÉVEILLE les disques en veille
#

set -euo pipefail