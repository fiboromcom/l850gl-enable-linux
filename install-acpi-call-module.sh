#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-/etc/default/l850gl-recovery}"
if [[ -r "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

L850GL_USER="${L850GL_USER:-${SUDO_USER:-aidan}}"
if [[ "$L850GL_USER" == "root" ]]; then
  L850GL_USER="aidan"
fi
L850GL_HOME="${L850GL_HOME:-/home/${L850GL_USER}}"

ACPI_SRC="${ACPI_SRC:-${L850GL_HOME}/src/acpi_call}"
KVER="$(uname -r)"
DEST_DIR="/lib/modules/${KVER}/extra"
DEST="${DEST_DIR}/acpi_call.ko"

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo: sudo $0"
  exit 1
fi

if [[ ! -d "$ACPI_SRC" ]]; then
  echo "Missing acpi_call source tree: $ACPI_SRC"
  echo "Override with:"
  echo "  sudo ACPI_SRC=/path/to/acpi_call $0"
  exit 1
fi

if [[ ! -d "/lib/modules/${KVER}/build" ]]; then
  echo "Missing kernel build tree for running kernel: ${KVER}"
  echo "Install matching kernel-devel first:"
  echo "  sudo dnf install kernel-devel-${KVER}"
  exit 1
fi

echo "Building acpi_call for kernel ${KVER} from ${ACPI_SRC}"
make -C "$ACPI_SRC" clean
make -C "$ACPI_SRC"

if [[ ! -f "${ACPI_SRC}/acpi_call.ko" ]]; then
  echo "Build completed but acpi_call.ko was not found"
  exit 1
fi

echo "Installing ${DEST}"
install -d -m 0755 "$DEST_DIR"
install -m 0644 "${ACPI_SRC}/acpi_call.ko" "$DEST"

restorecon -v "$DEST" 2>/dev/null || true
depmod -a "$KVER"

echo "Testing modprobe acpi_call"
modprobe acpi_call

if [[ ! -e /proc/acpi/call ]]; then
  echo "modprobe returned, but /proc/acpi/call is missing"
  exit 1
fi

ls -l /proc/acpi/call
echo "acpi_call installed and loadable via modprobe for ${KVER}"
