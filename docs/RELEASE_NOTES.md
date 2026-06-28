# Release notes

## v1.0

Bundled known-working state:

- Manual Hammer v1.3
- Boot Recovery v2.0
- Separate manual and boot paths
- Shared `/etc/default/l850gl-recovery` config
- acpi_call install helper
- MBIM udev rule
- diagnostics helper
- boot persistence via `l850gl-boot-rescue.service`
- FCC unlock prerequisite marker check in bootstrap

Confirmed boot-persistent with:

```text
cdc-wdm0           gsm       connected               voxi
Bus ... ID 2cb7:0007 Fibocom L850-GL
ExecStart=/usr/local/sbin/l850gl-boot-recovery.sh
code=exited, status=0/SUCCESS
BOOT RECOVERY SUCCESS
```
