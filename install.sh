#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo: sudo $0"
  exit 1
fi

TARGET_USER="${L850GL_USER:-${SUDO_USER:-aidan}}"
if [[ "$TARGET_USER" == "root" ]]; then
  TARGET_USER="aidan"
fi

TARGET_HOME="${L850GL_HOME:-$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6)}"
TARGET_HOME="${TARGET_HOME:-/home/${TARGET_USER}}"

CON_NAME="${CON_NAME:-voxi}"
APN="${APN:-wap.vodafone.co.uk}"
XMM2USB="${XMM2USB:-${TARGET_HOME}/src/xmm7360-usb-modeswitch/xmm2usb}"
ACPI_SRC="${ACPI_SRC:-${TARGET_HOME}/src/acpi_call}"

install -m 0755 "$DIR/scripts/l850gl-manual-rescue.sh" /usr/local/sbin/l850gl-manual-rescue.sh
install -m 0755 "$DIR/scripts/l850gl-boot-recovery.sh" /usr/local/sbin/l850gl-boot-recovery.sh
install -m 0644 "$DIR/systemd/l850gl-boot-rescue.service" /etc/systemd/system/l850gl-boot-rescue.service

# Shared runtime config for both scripts and the systemd unit.
cat > /etc/default/l850gl-recovery <<EOF
L850GL_USER=${TARGET_USER}
L850GL_HOME=${TARGET_HOME}
CON_NAME=${CON_NAME}
APN=${APN}
XMM2USB=${XMM2USB}
ACPI_SRC=${ACPI_SRC}
EOF
chmod 0644 /etc/default/l850gl-recovery

# Udev rule is also written by the scripts, but install it now for visibility/persistence.
install -m 0644 "$DIR/udev/78-l850gl-mbim.rules" /etc/udev/rules.d/78-l850gl-mbim.rules
udevadm control --reload || true

systemctl daemon-reload
systemctl enable l850gl-boot-rescue.service

echo "Installed X1 L850-GL Fedora Recovery v1.0"
echo
echo "Config:"
echo "  /etc/default/l850gl-recovery"
echo
echo "Manual Hammer:"
echo "  /usr/local/sbin/l850gl-manual-rescue.sh"
echo
echo "Boot recovery:"
echo "  /usr/local/sbin/l850gl-boot-recovery.sh"
echo "  /etc/systemd/system/l850gl-boot-rescue.service"
echo
echo "Detected paths:"
echo "  XMM2USB=${XMM2USB}"
echo "  ACPI_SRC=${ACPI_SRC}"
echo
echo "Next:"
echo "  sudo ./install-acpi-call-module.sh"
echo "  sudo systemctl start l850gl-boot-rescue.service"
