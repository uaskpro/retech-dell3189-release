# ReTech Dell 3189 Firmware Release v1.0.0

Release date: 2026-05-18

## Summary

This is the first validated public ReTech firmware release for Dell Chromebook
11 3189 / KEFKA.

Validated on physical hardware:

- Installer downloaded through `https://s4d.uk/dell3189`
- Board detection passed for `KEFKA`
- ROM downloaded and verified
- Existing SPI firmware backup created
- ReTech UEFI Full ROM flashed successfully
- UEFI NVRAM/SMMSTORE cleared
- ReTech splash displayed on boot

## Supported Device

Only this device is supported:

- Dell Chromebook 11 3189
- ChromeOS/coreboot board: `KEFKA`

Do not use this release on other Chromebook models.

## Install

Recommended environment: ChromeOS developer mode shell / VT2.

```sh
curl -fsSL -o dell3189.sh https://s4d.uk/dell3189
sudo bash dell3189.sh
```

The default flow uses stable firmware, asks one confirmation question with
`Y` as the default, flashes the verified ROM, clears UEFI NVRAM/SMMSTORE, and
reboots.

## Artifact Metadata

- ROM: `dell3189.rom`
- Firmware version: `ReTech-2603.1`
- Size: `8388608` bytes
- SHA256:
  `56b2a744aefec2112b513ff75cef223137692eb3981de053c1636341a348db06`
- Manifest: `manifest.json`
- Installer: `dell3189.sh`

## Requirements

- AC power connected
- Root shell access
- Firmware write protection disabled
- `flashrom`
- `curl` or `wget`
- `sha256sum`

On apt-based Linux, the installer can install missing dependencies. Some Linux
kernels block SPI access through `/dev/mem`; boot with `iomem=relaxed` or use
ChromeOS developer shell / VT2.

## Backup and Recovery

The installer creates a device-specific firmware backup before writing.

Default paths:

- Backups/work files: `/var/tmp/retech-dell3189/`
- Logs: `/var/log/retech-dell3189/`

Restore command:

```sh
sudo bash dell3189.sh --restore /path/to/backup-before-flash.rom
```

Some failures may require an external SPI programmer.

## Source and Attribution

This is a downstream package based on MrChromebox/coreboot and related upstream
projects. It does not replace MrChromebox or coreboot.

Upstream source reference:

- `MrChromebox/coreboot`
- Branch: `MrChromebox-2603`
- Commit: `f8244f2508d486d833eb8dee5c0b1d777cf37d39`

Source materials and build notes are published under `source/`.

## Known Limits

- No eMMC wipe
- No custom BIOS menu
- No multi-model selection
- No automatic fleet updater service yet

Planned future work includes a safer update flow for machines already running
MrChromebox or older ReTech firmware, plus a dedicated ReTech update USB image.
