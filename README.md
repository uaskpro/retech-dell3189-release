# ReTech Dell 3189 Firmware Release

Public release repository for the ReTech Dell Chromebook 11 3189 firmware
package.

This repository is intentionally narrow. It contains only the stable artifacts
and source materials needed to install and reproduce the Dell Chromebook 11
3189 / KEFKA firmware package.

## Release

- Release: `v1.0.0`
- Date: 2026-05-18
- Status: tested successfully on Dell Chromebook 11 3189 / KEFKA
- Firmware version: `ReTech-2603.1`

## Operator Install

Primary supported environment: ChromeOS developer mode shell / VT2.

Use the short link:

```sh
curl -fsSL -o dell3189.sh https://s4d.uk/dell3189
sudo bash dell3189.sh
```

Direct GitHub raw URL after this repository is published:

```sh
curl -fsSLO https://raw.githubusercontent.com/uaskpro/retech-dell3189-release/main/dell3189.sh
sudo bash dell3189.sh
```

Default behavior:

- Uses the stable ROM in `manifest.json`
- Checks board `KEFKA`
- Verifies ROM size and SHA256
- Backs up current SPI firmware
- Flashes the verified ROM through `flashrom`
- Clears UEFI NVRAM/SMMSTORE
- Reboots after a successful flash

The installer does not wipe eMMC.

## Requirements

- Dell Chromebook 11 3189 / board `KEFKA`
- AC power connected
- Firmware write protection disabled
- Root shell access
- `curl` or `wget`
- `flashrom`
- `sha256sum`

On apt-based Linux, the installer can install missing dependencies. Some Linux
kernels block SPI access through `/dev/mem`; boot with `iomem=relaxed` or use
ChromeOS developer shell / VT2.

## Files

- `dell3189.sh` - installer for operators
- `dell3189.rom` - ReTech UEFI Full ROM for Dell Chromebook 11 3189 / KEFKA
- `dell3189.rom.sha256` - checksum for the ROM
- `manifest.json` - stable channel metadata
- `source/` - build script, splash assets, and source compliance notes

## Firmware Metadata

- Device: Dell Chromebook 11 3189
- Board: KEFKA
- Firmware version: ReTech-2603.1
- ROM size: 8388608 bytes
- ROM SHA256:
  `56b2a744aefec2112b513ff75cef223137692eb3981de053c1636341a348db06`

## Recovery

The installer saves a device-specific backup before writing firmware. Keep that
backup until the device has passed QA.

Default paths:

- Work files and backups: `/var/tmp/retech-dell3189/`
- Logs: `/var/log/retech-dell3189/`

Restore command, when the machine still boots and `flashrom` can access SPI:

```sh
sudo bash dell3189.sh --restore /path/to/backup-before-flash.rom
```

Some failures require an external SPI programmer.

## Attribution

This is a downstream package built from MrChromebox/coreboot and related
upstream projects. It does not replace MrChromebox, coreboot, Tianocore/EDK2,
flashrom, or their contributors.

See `source/SOURCE-COMPLIANCE.md`.
