#!/usr/bin/env bash
# l850gl-manual-rescue.sh v1.3
#
# Manual-only rescue / bring-up script for Fibocom L850-GL / Intel XMM7360 on Fedora.
#
# This is the manual Hammer. It is intentionally separate from boot persistence.
# It does not install a systemd service and does not run unless manually invoked.
#
# v1.3:
#   - USB-first.
#   - Uses mmcli -m any instead of hard-coding modem index.
#   - Treats nmcli activation failure as provisional if voxi becomes connected anyway.
#
# No AT+CFUN. No AT+COPS. No NVM writes. No native PCI/RPC target path.

set -uo pipefail

VERSION="1.3"

ENV_FILE="${ENV_FILE:-/etc/default/l850gl-recovery}"
if [[ -r "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

resolve_user_home() {
  if [[ -z "${L850GL_USER:-}" ]]; then
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
      L850GL_USER="$SUDO_USER"
    elif [[ -n "${USER:-}" && "${USER}" != "root" ]]; then
      L850GL_USER="$USER"
    else
      L850GL_USER="$(awk -F: '$3 >= 1000 && $1 != "nobody" { print $1; exit }' /etc/passwd)"
    fi
  fi

  if [[ -z "${L850GL_USER:-}" ]]; then
    echo "ERROR: could not infer non-root user. Set L850GL_USER and L850GL_HOME in /etc/default/l850gl-recovery." >&2
    exit 1
  fi

  if [[ -z "${L850GL_HOME:-}" ]]; then
    L850GL_HOME="$(getent passwd "$L850GL_USER" 2>/dev/null | cut -d: -f6)"
  fi

  if [[ -z "${L850GL_HOME:-}" ]]; then
    echo "ERROR: could not infer home directory for $L850GL_USER. Set L850GL_HOME in /etc/default/l850gl-recovery." >&2
    exit 1
  fi
}

resolve_user_home

CON_NAME="${CON_NAME:-voxi}"
APN="${APN:-wap.vodafone.co.uk}"
XMM2USB="${XMM2USB:-${L850GL_HOME}/src/xmm7360-usb-modeswitch/xmm2usb}"
ACPI_SRC="${ACPI_SRC:-${L850GL_HOME}/src/acpi_call}"
STATE_DIR="${STATE_DIR:-${L850GL_HOME}/l850gl-clean-working-state}"
STATE_TAR="${STATE_TAR:-${L850GL_HOME}/l850gl-clean-working-state.tar.gz}"
LOG_DIR="${LOG_DIR:-/var/log/l850gl-manual-rescue}"
SELF_RECOVERY_WAIT="${SELF_RECOVERY_WAIT:-90}"
POST_UP_VERIFY_WAIT="${POST_UP_VERIFY_WAIT:-30}"
UDEV_RULE="/etc/udev/rules.d/78-l850gl-mbim.rules"

RUN_ID="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$LOG_DIR/run-$RUN_ID.log"

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

log() { printf '[%s] [l850gl-manual-rescue v%s] %s\n' "$(date --iso-8601=seconds)" "$VERSION" "$*"; }
have_cmd() { command -v "$1" >/dev/null 2>&1; }

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "Run as root: sudo $0"
    exit 1
  fi
}

usb_present() { lsusb | grep -qi '2cb7:0007'; }
pci_present() { lspci -nn | grep -Eiq '8086:7360|XMM7360|Cellular controller/modem'; }
voxi_connected() { nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device 2>/dev/null | grep -q "^cdc-wdm0:gsm:connected:${CON_NAME}$"; }

wait_for() {
  local label="$1"
  local timeout="$2"
  local cmd="$3"
  for ((i=1; i<=timeout; i++)); do
    if bash -lc "$cmd" >/dev/null 2>&1; then
      log "$label appeared after ${i}s"
      return 0
    fi
    sleep 1
  done
  log "WARNING: timed out waiting for $label"
  return 1
}

wait_for_voxi_connected() {
  local timeout="${1:-30}"
  for ((i=1; i<=timeout; i++)); do
    if voxi_connected; then
      log "${CON_NAME} is connected on cdc-wdm0 after ${i}s"
      return 0
    fi
    sleep 1
  done
  return 1
}

collect_state() {
  local tag="${1:-state}"
  local d="$STATE_DIR"
  mkdir -p "$d"

  log "Capturing state to $d"

  mmcli -m any > "$d/mmcli-m-any.txt" 2>&1 || true
  mmcli -L > "$d/mmcli-L.txt" 2>&1 || true
  nmcli device > "$d/nmcli-device.txt" 2>&1 || true
  nmcli connection show --active > "$d/nmcli-active.txt" 2>&1 || true
  nmcli connection show "$CON_NAME" > "$d/nmcli-${CON_NAME}.txt" 2>&1 || true
  nmcli -f NAME,UUID,TYPE,AUTOCONNECT connection show > "$d/nmcli-connections.txt" 2>&1 || true
  udevadm info --query=property --name=/dev/cdc-wdm0 > "$d/udev-cdc-wdm0.txt" 2>&1 || true
  rfkill list all > "$d/rfkill.txt" 2>&1 || true
  lspci -nnk > "$d/lspci-nnk.txt" 2>&1 || true
  lsusb > "$d/lsusb.txt" 2>&1 || true
  ip addr > "$d/ip-addr.txt" 2>&1 || true
  ip route > "$d/ip-route.txt" 2>&1 || true
  journalctl -u ModemManager -b --no-pager > "$d/journal-ModemManager.txt" 2>&1 || true
  journalctl -u NetworkManager -b --no-pager > "$d/journal-NetworkManager.txt" 2>&1 || true
  dmesg 2>/dev/null | grep -Ei 'fibocom|2cb7|8087|07f5|cdc|mbim|ttyACM|wwp|wwan|xmm|iosm' > "$d/dmesg-l850gl.txt" 2>&1 || true

  {
    echo "tag=$tag"
    echo "run_id=$RUN_ID"
    echo "version=$VERSION"
    echo "date=$(date --iso-8601=seconds)"
    echo "CON_NAME=$CON_NAME"
    echo "APN=$APN"
    echo "XMM2USB=$XMM2USB"
    echo "ACPI_SRC=$ACPI_SRC"
    echo "SELF_RECOVERY_WAIT=$SELF_RECOVERY_WAIT"
    echo "POST_UP_VERIFY_WAIT=$POST_UP_VERIFY_WAIT"
    echo "LOG_FILE=$LOG_FILE"
  } > "$d/summary.txt"

  tar -czf "$STATE_TAR" -C "$(dirname "$d")" "$(basename "$d")" 2>/dev/null || true
  log "State archive: $STATE_TAR"
}

fail() {
  log "ERROR: $*"
  collect_state "failed"
  exit 1
}

ensure_voxi_profile() {
  if nmcli -t -f NAME,TYPE connection show | grep -q "^${CON_NAME}:gsm$"; then
    log "Existing ${CON_NAME} GSM profile found"
  else
    log "Creating ${CON_NAME} GSM profile"
    nmcli connection add type gsm ifname "*" con-name "$CON_NAME" apn "$APN" || fail "Failed to create NM GSM profile"
  fi

  nmcli connection modify "$CON_NAME" gsm.apn "$APN" || true
  nmcli connection modify "$CON_NAME" connection.autoconnect yes
  nmcli connection modify "$CON_NAME" ipv4.method auto
  nmcli connection modify "$CON_NAME" ipv6.method ignore
}

need_root

for c in dnf uname rpm git make gcc systemctl rfkill lspci lsusb udevadm mmcli nmcli tar modprobe; do
  have_cmd "$c" || fail "Required command missing: $c"
done

log "Starting manual rescue"
log "CON_NAME=$CON_NAME APN=$APN XMM2USB=$XMM2USB ACPI_SRC=$ACPI_SRC SELF_RECOVERY_WAIT=$SELF_RECOVERY_WAIT POST_UP_VERIFY_WAIT=$POST_UP_VERIFY_WAIT"

if voxi_connected; then
  log "${CON_NAME} is already connected on cdc-wdm0; nothing to do"
  collect_state "already-connected"
  exit 0
fi

log "Waiting up to ${SELF_RECOVERY_WAIT}s for post-resume/self-recovery"
for ((i=1; i<=SELF_RECOVERY_WAIT; i++)); do
  if voxi_connected; then
    log "${CON_NAME} self-recovered on cdc-wdm0 after ${i}s; nothing to do"
    collect_state "self-recovered"
    exit 0
  fi
  sleep 1
done

log "No self-recovery detected; proceeding with manual rescue"

log "Installing/confirming required packages"
dnf install -y git make gcc kernel-devel kernel-headers ModemManager NetworkManager usbutils pciutils libmbim libmbim-utils picocom curl || fail "dnf package install/check failed"

RUNNING_KERNEL="$(uname -r)"
if ! rpm -q "kernel-devel-$RUNNING_KERNEL" >/dev/null 2>&1; then
  fail "kernel-devel for running kernel is missing: kernel-devel-$RUNNING_KERNEL"
fi
log "kernel-devel matches running kernel: $RUNNING_KERNEL"

[[ -d "$ACPI_SRC" ]] || fail "Missing acpi_call source tree: $ACPI_SRC"
[[ -d "$(dirname "$XMM2USB")" ]] || fail "Missing xmm7360-usb-modeswitch directory: $(dirname "$XMM2USB")"
[[ -x "$XMM2USB" ]] || fail "xmm2usb missing or not executable: $XMM2USB"

log "Checking xmm2usb for /proc/acpi/call guard"
grep -q '/proc/acpi/call' "$XMM2USB" || fail "xmm2usb does not appear to contain /proc/acpi/call guard"

log "Installing MBIM udev rule"
cat > "$UDEV_RULE" <<'EOF'
# Fibocom L850-GL / Intel XMM7360 in USB MBIM mode
ACTION!="add|change|move", GOTO="l850gl_mbim_end"
SUBSYSTEM=="usbmisc", KERNEL=="cdc-wdm*", ATTRS{idVendor}=="2cb7", ATTRS{idProduct}=="0007", ENV{ID_MM_CANDIDATE}="1", ENV{ID_MM_PORT_TYPE_MBIM}="1"
LABEL="l850gl_mbim_end"
EOF
udevadm control --reload || true

log "Stopping ModemManager"
systemctl stop ModemManager.service || true
sleep 2

log "Unblocking radios"
rfkill unblock wwan || true
rfkill unblock all || true

log "Rescanning PCI/USB state"
echo 1 > /sys/bus/pci/rescan || true
sleep 8

log "Device identity check"
lsusb | grep -Ei 'fibocom|2cb7|8087|07f5' || true
lspci -nn | grep -Ei '7360|cellular|wwan' || true

if usb_present; then
  log "USB 2cb7:0007 already present; modem is already in USB MBIM mode"
else
  log "USB 2cb7:0007 not present; checking PCI 8086:7360"
  pci_present || fail "Neither USB 2cb7:0007 nor PCI 8086:7360 is visible"

  log "Ensuring acpi_call"
  modprobe acpi_call >/dev/null 2>&1 || true

  if [[ ! -e /proc/acpi/call ]]; then
    log "Building/loading acpi_call from $ACPI_SRC"
    (
      cd "$ACPI_SRC" || exit 1
      make clean
      make
    ) || fail "acpi_call build failed"

    insmod "$ACPI_SRC/acpi_call.ko" || true
  fi

  [[ -e /proc/acpi/call ]] || fail "/proc/acpi/call still missing"

  lsmod | grep acpi_call || true
  ls -l /proc/acpi/call || true

  log "Running source-tree xmm2usb once"
  "$XMM2USB" || fail "xmm2usb failed"
  sleep 30
fi

log "Post-switch/recovery device check"
lsusb | grep -Ei 'fibocom|2cb7|8087|07f5' || true
ls -l /dev/cdc-wdm* /dev/ttyACM* 2>/dev/null || true
ip link | grep -E 'wwp|wwan' || true

wait_for "USB 2cb7:0007" 30 "lsusb | grep -qi '2cb7:0007'" || fail "USB 2cb7:0007 did not appear"
wait_for "/dev/cdc-wdm0" 30 "[[ -e /dev/cdc-wdm0 ]]" || fail "/dev/cdc-wdm0 did not appear"

log "Applying udev rule"
udevadm control --reload || true
udevadm trigger --action=change --subsystem-match=usbmisc || true
udevadm trigger --action=change --subsystem-match=usb || true
udevadm settle || true

log "Verifying cdc-wdm0 MBIM classification"
udevadm info --query=property --name=/dev/cdc-wdm0 | grep -Ei 'ID_MM|MBIM' || true
udevadm info --query=property --name=/dev/cdc-wdm0 | grep -q 'ID_MM_PORT_TYPE_MBIM=1' || fail "cdc-wdm0 not marked as MBIM"

log "Starting ModemManager"
systemctl start ModemManager.service || fail "Failed to start ModemManager"

log "Waiting for ModemManager to expose a modem"
wait_for "ModemManager modem" 45 "mmcli -L 2>/dev/null | grep -q '/Modem/'" || fail "No modem appeared in ModemManager"

log "ModemManager state"
mmcli -L || true
mmcli -m any || fail "mmcli -m any failed"

mmcli -m any | grep -q 'plugin: fibocom' || fail "ModemManager did not use fibocom plugin"
mmcli -m any | grep -q 'primary port: cdc-wdm0' || fail "ModemManager primary port is not cdc-wdm0"

log "Ensuring NetworkManager profile: $CON_NAME"
ensure_voxi_profile

log "Bringing up $CON_NAME"
if nmcli connection up "$CON_NAME"; then
  log "nmcli reported ${CON_NAME} activation success"
else
  log "WARNING: nmcli connection up ${CON_NAME} failed; verifying final connection state for ${POST_UP_VERIFY_WAIT}s before declaring failure"
  if wait_for_voxi_connected "$POST_UP_VERIFY_WAIT"; then
    log "${CON_NAME} is connected despite nmcli activation failure; treating as success"
  else
    fail "nmcli connection up ${CON_NAME} failed and ${CON_NAME} did not become connected"
  fi
fi

log "Final modem/network state"
mmcli -m any || true
nmcli device || true
if have_cmd curl; then
  curl -I --max-time 20 https://example.com || true
else
  log "curl not installed; skipping external HTTP check"
fi

collect_state "success"

log "MANUAL RESCUE SUCCESS"
exit 0
