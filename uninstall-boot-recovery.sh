#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo: sudo $0"
  exit 1
fi

systemctl disable --now l850gl-boot-rescue.service 2>/dev/null || true
rm -f /etc/systemd/system/l850gl-boot-rescue.service
rm -f /usr/local/sbin/l850gl-boot-recovery.sh
systemctl daemon-reload

echo "Removed boot recovery service and boot recovery script."
echo "Manual Hammer remains:"
echo "  /usr/local/sbin/l850gl-manual-rescue.sh"
echo
echo "Shared config remains:"
echo "  /etc/default/l850gl-recovery"
