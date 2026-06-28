# X1 L850-GL Fedora Recovery v1.0

Working recovery bundle for a ThinkPad X1 Carbon with Fibocom L850-GL / Intel XMM7360 on Fedora.

This bundle is intentionally conservative: preserve basic function over speed.

## What this contains

Manual Hammer:

```text
/usr/local/sbin/l850gl-manual-rescue.sh
```

Boot recovery:

```text
/usr/local/sbin/l850gl-boot-recovery.sh
/etc/systemd/system/l850gl-boot-rescue.service
```

Shared config:

```text
/etc/default/l850gl-recovery
```

The boot service calls only the boot recovery script. It does **not** call the manual Hammer.

## External source trees required

This package does not vendor the external source trees. It expects them to exist locally:

```text
~/src/acpi_call
~/src/xmm7360-usb-modeswitch
```

By default, `install.sh` detects the sudoing user and writes the paths to:

```text
/etc/default/l850gl-recovery
```

For another layout, set overrides before installing:

```bash
sudo L850GL_USER="$USER" \
  L850GL_HOME="$HOME" \
  XMM2USB="$HOME/src/xmm7360-usb-modeswitch/xmm2usb" \
  ACPI_SRC="$HOME/src/acpi_call" \
  ./install.sh
```

## Known-good result

After boot:

```text
cdc-wdm0  gsm  connected  voxi
USB 2cb7:0007 Fibocom L850-GL
ModemManager plugin: fibocom
primary port: cdc-wdm0
l850gl-boot-rescue.service: status=0/SUCCESS
```

## Known-good path

Boot state:

```text
USB 2cb7:0007 absent
PCI 8086:7360 present
No ModemManager modem
```

Recovery path:

```text
modprobe acpi_call
/proc/acpi/call present
xmm2usb once
USB 2cb7:0007 appears
/dev/cdc-wdm0 appears
udev marks MBIM
ModemManager adopts Fibocom L850-GL using cdc-wdm0
NetworkManager brings up voxi
```

## Install

From the extracted directory:

```bash
sudo ./install.sh
sudo ./install-acpi-call-module.sh
```

Then test without reboot:

```bash
sudo systemctl reset-failed l850gl-boot-rescue.service
sudo systemctl start l850gl-boot-rescue.service
systemctl status l850gl-boot-rescue.service --no-pager -l
```

Reboot test:

```bash
sudo reboot
```

After login, wait 60-90 seconds, then:

```bash
./diagnostics.sh
```

## Manual fallback

```bash
sudo /usr/local/sbin/l850gl-manual-rescue.sh
```

## Boot recovery logs

```bash
journalctl -u l850gl-boot-rescue.service -b --no-pager -l
ls -lt /var/log/l850gl-boot-recovery/ | head
```

## Manual Hammer logs

```bash
ls -lt /var/log/l850gl-manual-rescue/ | head
```

## Remove boot persistence only

```bash
sudo ./uninstall-boot-recovery.sh
```

This removes:

```text
/etc/systemd/system/l850gl-boot-rescue.service
/usr/local/sbin/l850gl-boot-recovery.sh
```

It leaves the manual Hammer installed.

## Kernel update maintenance

After a kernel update, if boot recovery fails and `/proc/acpi/call` is missing:

```bash
sudo ./install-acpi-call-module.sh
```

## Safety rules

This bundle avoids:

```text
AT+CFUN
AT+COPS
modem NVM writes
native PCI/RPC target path
sleep/resume hooks
```

## Current caveat

Boot recovery is intentionally conservative and may take around 90 seconds.
