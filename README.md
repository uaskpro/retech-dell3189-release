# ReTech Dell 3189 Firmware Release

Public release repository for the ReTech Dell Chromebook 11 3189 firmware
package.

This repository is intentionally narrow. It contains only the stable artifacts
and source materials needed to install and reproduce the Dell Chromebook 11
3189 / KEFKA firmware package.

## Operator Install

Use the short link when configured:

```sh
curl -fsSL -o dell3189.sh https://s4d.uk/dell3189
sudo bash dell3189.sh
```

Direct GitHub raw URL after this repository is published:

```sh
curl -fsSLO https://raw.githubusercontent.com/uaskpro/retech-dell3189-release/main/dell3189.sh
sudo bash dell3189.sh
```

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

## Attribution

This is a downstream package built from MrChromebox/coreboot and related
upstream projects. It does not replace MrChromebox, coreboot, Tianocore/EDK2,
flashrom, or their contributors.

See `source/SOURCE-COMPLIANCE.md`.
