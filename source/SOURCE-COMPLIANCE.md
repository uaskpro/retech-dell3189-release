# Source Compliance

This public repository distributes a binary firmware ROM. The corresponding
source materials and build instructions are published here to keep attribution
and license obligations clear.

## Distributed Binary

- File: `dell3189.rom`
- Device: Dell Chromebook 11 3189
- Board: KEFKA
- Firmware version: ReTech-2603.1
- SHA256: `56b2a744aefec2112b513ff75cef223137692eb3981de053c1636341a348db06`
- Size: `8388608` bytes

## Upstream Source

- MrChromebox/coreboot
- Branch: `MrChromebox-2603`
- Commit: `f8244f2508d486d833eb8dee5c0b1d777cf37d39`
- Original coreboot project: https://coreboot.org/
- EDK2/Tianocore payload is built through the MrChromebox/coreboot tree.

## Downstream Changes

The downstream changes for this release are intentionally small:

- Set the build version to `ReTech-2603.1` using `KERNELVERSION`.
- Use the Dell 3189 / KEFKA UEFI config from MrChromebox/coreboot:
  `configs/bsw/config.kefka.uefi`.
- Provide a ReTech EDK2 splash image:
  `source/bootsplash-edk2.png`.
- Package a focused installer:
  `dell3189.sh`.

## Rebuild Instructions

On Ubuntu/Debian or WSL:

```sh
git clone https://github.com/uaskpro/retech-dell3189-release.git
cd retech-dell3189-release
bash source/build-dell3189-rom.sh
```

The build script clones MrChromebox/coreboot, checks out `MrChromebox-2603`,
prepares the EDK2 splash asset, builds KEFKA, and writes the output ROM.

## Notes

The installer flashes only the firmware ROM. It does not wipe or modify the
internal eMMC storage.
