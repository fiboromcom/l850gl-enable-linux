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

## Prerequisite: FCC lock cleared

This enable repo assumes the L850-GL FCC lock has already been cleared.

Run the prerequisite repo first:

```bash
sudo dnf install -y git
git clone https://github.com/fiboromcom/l850gl-fcc-unlock-linux.git
cd l850gl-fcc-unlock-linux
./bootstrap-fedora.sh --yes-i-understand-regulatory-risk
```

That writes the marker consumed by this repo:

```text
/etc/l850gl-fcc-unlock.done
```

If the FCC lock was already cleared manually before using this repo:

```bash
sudo touch /etc/l850gl-fcc-unlock.done
```

To bypass the bootstrap check for one run:

```bash
SKIP_FCC_PREREQ_CHECK=1 ./bootstrap-fedora.sh
```


## Fresh Fedora bootstrap

After a clean Fedora install, connect with Wi-Fi, Ethernet, or USB tethering first.

```bash
sudo dnf install -y git
git clone https://github.com/fiboromcom/l850gl-enable-linux.git
cd l850gl-enable-linux
./bootstrap-fedora.sh
```

The bootstrap script installs Fedora dependencies, clones the two external source trees into `~/src`, installs this recovery bundle, and builds/installs `acpi_call` for the running kernel.

External repos used by the bootstrap script:

```text
https://github.com/mkottman/acpi_call.git
https://github.com/xmm7360/xmm7360-usb-modeswitch.git
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
