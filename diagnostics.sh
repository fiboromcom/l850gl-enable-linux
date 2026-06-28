#!/usr/bin/env bash
set -uo pipefail

echo "== NetworkManager device =="
nmcli device | grep -Ei 'cdc-wdm0|gsm|voxi' || true
echo

echo "== ModemManager list =="
mmcli -L || true
echo

echo "== USB =="
lsusb | grep -Ei 'fibocom|2cb7|8087|07f5' || true
echo

echo "== PCI =="
lspci -nn | grep -Ei '7360|cellular|wwan' || true
echo

echo "== Boot service =="
systemctl status l850gl-boot-rescue.service --no-pager -l || true
echo

echo "== Boot service journal =="
journalctl -u l850gl-boot-rescue.service -b --no-pager -l || true
