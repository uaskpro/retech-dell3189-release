#!/usr/bin/env bash
set -euo pipefail

BOARD="kefka"
UPSTREAM_REPO="https://github.com/MrChromebox/coreboot.git"
UPSTREAM_BRANCH="MrChromebox-2603"
RETECH_VERSION_TAG="ReTech-2603.1"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGO_FILE="${PROJECT_DIR}/source/bootsplash-logo.png"
SPLASH_FILE="${PROJECT_DIR}/source/bootsplash-preview.png"
EDK2_SPLASH_FILE="${PROJECT_DIR}/source/bootsplash-edk2.png"
OUTPUT_ROM="${PROJECT_DIR}/dell3189.rom"
OUTPUT_SHA256="${OUTPUT_ROM}.sha256"
BUILD_ROOT="${HOME}/retech-coreboot-build"
COREBOOT_DIR="${BUILD_ROOT}/coreboot"

need_file() {
  if [ ! -f "$1" ]; then
    echo "Missing required file: $1" >&2
    exit 1
  fi
}

install_deps() {
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y \
      bison build-essential curl flex git gnat imagemagick \
      libcmocka-dev libncurses5-dev libnss3-dev libssl-dev \
      m4 nasm pkg-config python-is-python3 uuid-dev zlib1g-dev
  else
    echo "This script currently expects Debian/Ubuntu with apt-get." >&2
    exit 1
  fi
}

clone_or_update_coreboot() {
  mkdir -p "$BUILD_ROOT"

  if [ ! -d "$COREBOOT_DIR/.git" ]; then
    git clone "$UPSTREAM_REPO" "$COREBOOT_DIR"
  fi

  cd "$COREBOOT_DIR"
  git fetch origin "$UPSTREAM_BRANCH"
  git checkout "$UPSTREAM_BRANCH"
  git reset --hard "origin/${UPSTREAM_BRANCH}"
  git submodule update --init --checkout --recursive
}

prepare_bootsplash() {
  local im_cmd="convert"
  local identify_cmd="identify"
  local tmp_logo="${PROJECT_DIR}/source/bootsplash-logo-trimmed.png"

  if command -v magick >/dev/null 2>&1; then
    im_cmd="magick"
    identify_cmd="magick identify"
  elif ! command -v convert >/dev/null 2>&1; then
    echo "ImageMagick is installed, but neither magick nor convert is available in PATH." >&2
    exit 1
  fi

  echo "Preparing compact EDK2 logo asset from transparent source..."
  $im_cmd "$LOGO_FILE" -trim +repage "$tmp_logo"
  $im_cmd "$tmp_logo" -background black -alpha remove -alpha off "PNG24:${EDK2_SPLASH_FILE}"
  need_file "$EDK2_SPLASH_FILE"

  splash_size="$($identify_cmd -format '%wx%h' "$EDK2_SPLASH_FILE")"
  echo "Prepared EDK2 bootsplash: $EDK2_SPLASH_FILE ($splash_size)"

  echo "Rendering centered 1024x768 preview..."
  $im_cmd -size 1024x768 canvas:black "$tmp_logo" -gravity center -composite "PNG24:${SPLASH_FILE}"
  rm -f "$tmp_logo"
}

build_rom() {
  cd "$COREBOOT_DIR"

  make crossgcc-i386 CPUS="$(nproc)"

  rm -rf build
  cp "configs/bsw/config.${BOARD}.uefi" .config
  echo "CONFIG_EDK2_BOOTSPLASH_FILE=\"${EDK2_SPLASH_FILE}\"" >> .config

  make clean
  make KERNELVERSION="$RETECH_VERSION_TAG" olddefconfig
  make KERNELVERSION="$RETECH_VERSION_TAG" -j"$(nproc)"

  cp build/coreboot.rom "$OUTPUT_ROM"
  sha256sum "$OUTPUT_ROM" > "$OUTPUT_SHA256"
}

main() {
  need_file "$LOGO_FILE"
  echo "== Installing build dependencies =="
  install_deps
  echo "== Updating MrChromebox/coreboot source =="
  clone_or_update_coreboot
  echo "== Preparing ReTech bootsplash =="
  prepare_bootsplash
  echo "== Building Dell 3189 / KEFKA ROM =="
  build_rom

  echo
  echo "Built ROM:"
  echo "  $OUTPUT_ROM"
  echo
  cat "$OUTPUT_SHA256"
}

main "$@"
