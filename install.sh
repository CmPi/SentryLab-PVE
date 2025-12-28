#!/bin/bash
#
# @file install.sh
# @author CmPi <cmpi@webe.fr>
# @repo https://github.com/CmPi/SentryLab-PVE
# @brief Installe les scripts et services SentryLab sans les activer
# @date 2025-12-27
# @version 1.1.361
# @usage sudo ./install.sh
#

set -e

# Vérification root
if [ "$EUID" -ne 0 ]; then echo "Veuillez lancer en root"; exit 1; fi

echo "--- INSTALLATION SENTRYLAB-PVE ---"

# 1. Création des dossiers
mkdir -p /usr/local/bin/sentrylab

# 2. Déploiement des scripts
echo "Déploiement des scripts vers /usr/local/bin/..."
cp scripts/*.sh /usr/local/bin/
chmod +x /usr/local/bin/sentrylab-*.sh

# 3. Déploiement Systemd
echo "Déploiement des unités Systemd..."
cp scripts/*.{service,timer} /etc/systemd/system/
systemctl daemon-reload

# 4. Déploiement des utilitaires de gestion
# On les copie avec leurs nouveaux noms de commande
cp sentrylab-start.sh /usr/local/bin/sentrylab-start
cp sentrylab-stop.sh /usr/local/bin/sentrylab-stop
chmod +x /usr/local/bin/sentrylab-start /usr/local/bin/sentrylab-stop

echo "Terminé. Vous pouvez tester en mode debug avant de lancer 'sentrylab-start'."