#!/usr/bin/env bash
# bootstrap-fedora.sh
#
# Fresh Fedora bootstrap for ThinkPad X1 Carbon + Fibocom L850-GL / Intel XMM7360.
#
# Run from this repository after cloning it:
#
#   git clone https://github.com/fiboromcom/l850gl-enable-linux.git
#   cd l850gl-enable-linux
#   ./bootstrap-fedora.sh
#
# This script:
#   - installs Fedora package dependencies
#   - clones/updates the required external source trees into ~/src
#   - installs this recovery bundle
#   - builds/installs acpi_call for the running kernel
#
# It does not vendor the external projects.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

L850GL_USER="${L850GL_USER:-$(id -un)}"
L850GL_HOME="${L850GL_HOME:-$HOME}"
SRC_DIR="${SRC_DIR:-${L850GL_HOME}/src}"

ACPI_REPO="${ACPI_REPO:-https://github.com/mkottman/acpi_call.git}"
XMM_REPO="${XMM_REPO:-https://github.com/xmm7360/xmm7360-usb-modeswitch.git}"

ACPI_SRC="${ACPI_SRC:-${SRC_DIR}/acpi_call}"
XMM_SRC="${XMM_SRC:-${SRC_DIR}/xmm7360-usb-modeswitch}"
XMM2USB="${XMM2USB:-${XMM_SRC}/xmm2usb}"

CON_NAME="${CON_NAME:-voxi}"
APN="${APN:-wap.vodafone.co.uk}"

log() {
  printf '[bootstrap-fedora] %s\n' "$*"
}

clone_or_update() {
  local url="$1"
  local dest="$2"

  if [[ -d "$dest/.git" ]]; then
    log "Updating existing repo: $dest"
    git -C "$dest" pull --ff-only
  elif [[ -e "$dest" ]]; then
    echo "ERROR: $dest exists but is not a git repo"
    exit 1
  else
    log "Cloning $url -> $dest"
    git clone "$url" "$dest"
  fi
}


if [[ "${SKIP_FCC_PREREQ_CHECK:-0}" != "1" && ! -f /etc/l850gl-fcc-unlock.done ]]; then
  cat <<'EOF'
ERROR: FCC unlock prerequisite marker not found:

  /etc/l850gl-fcc-unlock.done

Run the prerequisite repo first:

  git clone https://github.com/fiboromcom/l850gl-fcc-unlock-linux.git
  cd l850gl-fcc-unlock-linux
  ./bootstrap-fedora.sh --yes-i-understand-regulatory-risk

If you have already cleared the FCC lock manually and accept responsibility:

  sudo touch /etc/l850gl-fcc-unlock.done

Or bypass this check for one run:

  SKIP_FCC_PREREQ_CHECK=1 ./bootstrap-fedora.sh

EOF
  exit 2
fi

log "Installing Fedora package dependencies"
sudo dnf install -y \
  git make gcc kernel-devel kernel-headers \
  ModemManager NetworkManager \
  usbutils pciutils \
  libmbim libmbim-utils \
  picocom curl

KVER="$(uname -r)"
if ! rpm -q "kernel-devel-${KVER}" >/dev/null 2>&1; then
  log "WARNING: exact kernel-devel package for running kernel was not confirmed: kernel-devel-${KVER}"
  log "If acpi_call build fails, update/reboot or install matching kernel-devel manually."
fi

log "Preparing source directory: $SRC_DIR"
mkdir -p "$SRC_DIR"

clone_or_update "$ACPI_REPO" "$ACPI_SRC"
clone_or_update "$XMM_REPO" "$XMM_SRC"

if [[ ! -f "$XMM2USB" ]]; then
  echo "ERROR: xmm2usb not found at: $XMM2USB"
  exit 1
fi

chmod +x "$XMM2USB" || true

log "Installing local recovery bundle"
sudo \
  L850GL_USER="$L850GL_USER" \
  L850GL_HOME="$L850GL_HOME" \
  XMM2USB="$XMM2USB" \
  ACPI_SRC="$ACPI_SRC" \
  CON_NAME="$CON_NAME" \
  APN="$APN" \
  "$REPO_DIR/install.sh"

log "Building/installing acpi_call module for running kernel"
sudo \
  L850GL_USER="$L850GL_USER" \
  L850GL_HOME="$L850GL_HOME" \
  XMM2USB="$XMM2USB" \
  ACPI_SRC="$ACPI_SRC" \
  CON_NAME="$CON_NAME" \
  APN="$APN" \
  "$REPO_DIR/install-acpi-call-module.sh"

log "Bootstrap complete"
echo
echo "Config:"
echo "  /etc/default/l850gl-recovery"
echo
echo "Manual fallback:"
echo "  sudo /usr/local/sbin/l850gl-manual-rescue.sh"
echo
echo "Test boot recovery without reboot:"
echo "  sudo systemctl reset-failed l850gl-boot-rescue.service"
echo "  sudo systemctl start l850gl-boot-rescue.service"
echo "  systemctl status l850gl-boot-rescue.service --no-pager -l"
echo
echo "Then reboot:"
echo "  sudo reboot"
