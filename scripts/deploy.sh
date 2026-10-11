#!/usr/bin/env bash
# Deploy custom Wazuh rules from this repo to the local Wazuh manager.
# Safe order: validate -> back up -> copy -> test config -> restart -> health check.
set -Eeuo pipefail          # stop at the first error

SRC="rules"                                                # rules folder inside this repo
DEST="/var/ossec/etc/rules"                                # Wazuh's custom rules folder
BACKUP="/var/backups/wazuh-rules-$(date +%Y%m%d-%H%M%S)"   # backup folder named with the time

# 1. Check that every rule file is valid XML
shopt -s nullglob
files=("$SRC"/*.xml)
(( ${#files[@]} )) || { echo "No rule files found"; exit 1; }
for f in "${files[@]}"; do xmllint --noout "$f"; done

# 2. Back up the current rules
sudo mkdir -p "$BACKUP"
sudo rsync -a "$DEST"/ "$BACKUP"/

# 3. Sync the managed files (names like 100-something.xml) with the right owner and permissions.
#    Files removed from the repo are removed from Wazuh. Other files such as local_rules.xml are left alone.
sudo rsync -a --delete --chown=root:wazuh --chmod=F660 \
  --include='[0-9][0-9][0-9]-*.xml' --exclude='*' "$SRC"/ "$DEST"/

# 4. Test the Wazuh configuration. If it fails, restore the backup and stop.
if ! sudo /var/ossec/bin/wazuh-analysisd -t; then
  echo "Config test failed - restoring backup"
  sudo rsync -a --delete "$BACKUP"/ "$DEST"/
  exit 1
fi

# 5. Restart Wazuh and check that it is running
sudo systemctl restart wazuh-manager
sleep 5
if systemctl is-active --quiet wazuh-manager; then
  echo "Deployed OK. Backup saved in $BACKUP"
else
  echo "Manager is not running - check: sudo systemctl status wazuh-manager"
  exit 1
fi
