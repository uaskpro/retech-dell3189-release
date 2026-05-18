#!/usr/bin/env bash
set -Eeuo pipefail

TOOLKIT_NAME="ReTech Dell 3189 Firmware Toolkit"
DEVICE_NAME="Dell Chromebook 11 3189"
EXPECTED_BOARD="KEFKA"
BOARD_ALIASES="KEFKA kefka GOOGLE_KEFKA"
DEFAULT_CHANNEL="stable"
ROM_NAME="dell3189.rom"
ROM_VERSION="ReTech-2603.1"
ROM_SHA256="56b2a744aefec2112b513ff75cef223137692eb3981de053c1636341a348db06"
ROM_SIZE="8388608"
RELEASE_BASE_URL="${CFT_RELEASE_BASE_URL:-https://raw.githubusercontent.com/uaskpro/retech-dell3189-release/main}"
SCRIPT_URL="${CFT_SCRIPT_URL:-https://s4d.uk/dell3189.sh}"
FLASHROM_PROGRAMMER="${CFT_FLASHROM_PROGRAMMER:-internal:boardmismatch=force}"
AUTO_INSTALL="${CFT_AUTO_INSTALL:-1}"
WORKDIR="${CFT_WORKDIR:-/var/tmp/retech-dell3189}"
LOGDIR="${CFT_LOGDIR:-/var/log/retech-dell3189}"
YES="${CFT_YES:-0}"
DEBUG="${CFT_DEBUG:-0}"
COLOR="${CFT_COLOR:-auto}"
CHANNEL="$DEFAULT_CHANNEL"
ACTION="flash"
MANIFEST_OVERRIDE=""
ROM_OVERRIDE=""
RESTORE_FILE=""
REBOOT_AFTER_FLASH="${CFT_REBOOT:-1}"
RUN_ID="${CFT_RUN_ID:-}"
RUN_DIR="$WORKDIR/$RUN_ID"
LOG_FILE="$LOGDIR/run-$RUN_ID.log"
BACKUP_FILE="$RUN_DIR/backup-before-flash-$RUN_ID.rom"
SCRIPT_PATH="${BASH_SOURCE[0]}"
if [[ "$SCRIPT_PATH" == */* ]]; then
  SCRIPT_DIR="$(cd "${SCRIPT_PATH%/*}" && pwd)"
else
  SCRIPT_DIR="$(pwd)"
fi

MANIFEST_FILE=""
MANIFEST_DEVICE="$DEVICE_NAME"
MANIFEST_BOARD="$EXPECTED_BOARD"
MANIFEST_VERSION="$ROM_VERSION"
MANIFEST_SHA256="$ROM_SHA256"
MANIFEST_SIZE="$ROM_SIZE"
MANIFEST_ROM_URL=""
MANIFEST_MIRROR_1=""
MANIFEST_MIRROR_2=""
ROM_PATH="$RUN_DIR/$ROM_NAME"

usage() {
  cat <<EOF
$TOOLKIT_NAME

Usage:
  sudo bash dell3189.sh [options]

Options:
  --channel stable|testing|latest  Select release channel (default: stable)
  --manifest URL_OR_PATH           Use a specific manifest
  --rom URL_OR_PATH                Use a specific ROM source
  --info                           Show detected firmware/device info only
  --backup-only                    Back up current firmware and stop
  --restore FILE                   Restore a previous backup ROM
  --flash                          Explicitly run the default flash flow
  --menu                           Show the advanced menu
  -y, --yes                        Unattended confirmation
  --no-reboot                      Do not reboot after a successful flash
  --debug                          Verbose shell trace and extra logging
  --no-color                       Disable colored output
  -h, --help                       Show this help

Environment:
  CFT_RELEASE_BASE_URL             Base URL for GitHub Releases or mirror
  CFT_WORKDIR                      Work and backup directory
  CFT_LOGDIR                       Log directory
  CFT_FLASHROM_PROGRAMMER          flashrom programmer string
  CFT_AUTO_INSTALL=0               Disable apt-based dependency install
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --channel)
        CHANNEL="${2:-}"
        shift 2
        ;;
      --manifest)
        MANIFEST_OVERRIDE="${2:-}"
        shift 2
        ;;
      --rom)
        ROM_OVERRIDE="${2:-}"
        shift 2
        ;;
      --info)
        ACTION="info"
        shift
        ;;
      --backup-only)
        ACTION="backup"
        shift
        ;;
      --restore)
        ACTION="restore"
        RESTORE_FILE="${2:-}"
        shift 2
        ;;
      --flash)
        ACTION="flash"
        shift
        ;;
      --menu)
        ACTION="menu"
        shift
        ;;
      -y|--yes)
        YES="1"
        shift
        ;;
      --no-reboot)
        REBOOT_AFTER_FLASH="0"
        shift
        ;;
      --debug)
        DEBUG="1"
        shift
        ;;
      --no-color)
        COLOR="0"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        printf 'Unknown option: %s\n\n' "$1" >&2
        usage >&2
        exit 2
        ;;
    esac
  done

  case "$CHANNEL" in
    stable|testing|latest) ;;
    *) printf 'Unsupported channel: %s\n' "$CHANNEL" >&2; exit 2 ;;
  esac
}

setup_color() {
  if [[ "$COLOR" == "0" || ( "$COLOR" == "auto" && ! -t 1 ) ]]; then
    BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; RESET=""
    return 0
  fi

  BOLD="$(printf '\033[1m')"
  DIM="$(printf '\033[2m')"
  RED="$(printf '\033[31m')"
  GREEN="$(printf '\033[32m')"
  YELLOW="$(printf '\033[33m')"
  BLUE="$(printf '\033[34m')"
  RESET="$(printf '\033[0m')"
}

log() {
  printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" | tee -a "$LOG_FILE"
}

say() {
  printf '%b\n' "$*" | tee -a "$LOG_FILE"
}

fail() {
  say "${RED}ERROR:${RESET} $*"
  log "Installer stopped."
  exit 1
}

debug() {
  if [[ "$DEBUG" == "1" ]]; then
    log "DEBUG: $*"
  fi
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    printf 'Run with root privileges:\n  curl -fsSLO %s && sudo bash dell3189.sh\n' "$SCRIPT_URL" >&2
    exit 1
  fi
}

init_runtime() {
  if [[ -z "$RUN_ID" ]]; then
    RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
    RUN_DIR="$WORKDIR/$RUN_ID"
    LOG_FILE="$LOGDIR/run-$RUN_ID.log"
    BACKUP_FILE="$RUN_DIR/backup-before-flash-$RUN_ID.rom"
  fi

  mkdir -p "$RUN_DIR" "$LOGDIR"
  touch "$LOG_FILE"
  [[ "$DEBUG" == "1" ]] && set -x
  log "Starting $TOOLKIT_NAME"
  log "Run ID: $RUN_ID"
}

is_url() {
  [[ "$1" == http://* || "$1" == https://* ]]
}

download_file() {
  local url="$1"
  local output="$2"
  local tmp="$output.tmp"

  rm -f "$tmp"
  log "Downloading: $url"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --connect-timeout 20 --retry 3 --retry-delay 2 -o "$tmp" "$url" 2>&1 | tee -a "$LOG_FILE"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$tmp" --tries=3 --timeout=20 "$url" 2>&1 | tee -a "$LOG_FILE"
  else
    fail "Neither curl nor wget is available."
  fi

  [[ -s "$tmp" ]] || fail "Download failed or produced an empty file: $url"
  mv -f "$tmp" "$output"
}

try_download_file() {
  local url="$1"
  local output="$2"
  local tmp="$output.tmp"

  rm -f "$tmp"
  log "Downloading: $url"
  if command -v curl >/dev/null 2>&1; then
    if ! curl -fL --connect-timeout 20 --retry 3 --retry-delay 2 -o "$tmp" "$url" 2>&1 | tee -a "$LOG_FILE"; then
      rm -f "$tmp"
      return 1
    fi
  elif command -v wget >/dev/null 2>&1; then
    if ! wget -O "$tmp" --tries=3 --timeout=20 "$url" 2>&1 | tee -a "$LOG_FILE"; then
      rm -f "$tmp"
      return 1
    fi
  else
    fail "Neither curl nor wget is available."
  fi

  [[ -s "$tmp" ]] || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$output"
}

copy_or_download() {
  local source="$1"
  local output="$2"

  if is_url "$source"; then
    download_file "$source" "$output"
  else
    [[ -f "$source" ]] || fail "File not found: $source"
    cp -f "$source" "$output"
  fi
}

try_copy_or_download() {
  local source="$1"
  local output="$2"

  if is_url "$source"; then
    try_download_file "$source" "$output"
  else
    [[ -f "$source" ]] || return 1
    cp -f "$source" "$output"
  fi
}

install_missing_deps() {
  local missing=("$@")

  [[ "${#missing[@]}" -gt 0 ]] || return 0
  [[ "$AUTO_INSTALL" == "1" ]] || fail "Missing required utilities: ${missing[*]}"

  if command -v apt-get >/dev/null 2>&1; then
    say "${YELLOW}Installing missing dependencies:${RESET} ${missing[*]}"
    apt-get update 2>&1 | tee -a "$LOG_FILE"
    apt-get install -y "${missing[@]}" 2>&1 | tee -a "$LOG_FILE"
    return 0
  fi

  fail "Missing required utilities: ${missing[*]}. Automatic install is available only on apt-based Linux."
}

require_commands() {
  local missing=()
  local command package

  for command in flashrom sha256sum awk sed grep tr date tee mkdir wc cp; do
    if ! command -v "$command" >/dev/null 2>&1; then
      case "$command" in
        sha256sum|tr|date|tee|mkdir|wc|cp) package="coreutils" ;;
        awk) package="gawk" ;;
        grep) package="grep" ;;
        sed) package="sed" ;;
        *) package="$command" ;;
      esac
      missing+=("$package")
    fi
  done

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    missing+=("curl")
  fi

  install_missing_deps "${missing[@]}"
}

read_first_existing_file() {
  local path
  for path in "$@"; do
    if [[ -r "$path" ]]; then
      tr -d '\000' <"$path" | sed 's/[[:space:]]*$//'
      return 0
    fi
  done
  return 1
}

normalize_board() {
  local raw upper
  raw="$1"
  upper="$(printf '%s' "$raw" | tr '[:lower:]' '[:upper:]')"

  if [[ "$upper" =~ (^|[^A-Z0-9])KEFKA([^A-Z0-9]|$) ]]; then
    printf 'KEFKA'
    return 0
  fi

  printf '%s' "$upper"
}

detect_board() {
  local board=""

  board="$(read_first_existing_file \
    /sys/devices/virtual/dmi/id/board_name \
    /sys/class/dmi/id/board_name \
    2>/dev/null || true)"

  if [[ -z "$board" && -r /etc/lsb-release ]]; then
    board="$(grep -E '^CHROMEOS_RELEASE_BOARD=' /etc/lsb-release 2>/dev/null \
      | sed 's/^CHROMEOS_RELEASE_BOARD=//' \
      | sed 's/-signed-mp.*$//' \
      | sed 's/-signed.*$//' || true)"
  fi

  normalize_board "$board"
}

detect_model() {
  read_first_existing_file \
    /sys/devices/virtual/dmi/id/product_name \
    /sys/class/dmi/id/product_name \
    2>/dev/null || true
}

detect_ac_power() {
  local supply online
  for supply in /sys/class/power_supply/*/online; do
    [[ -r "$supply" ]] || continue
    online="$(tr -d '[:space:]' <"$supply")"
    [[ "$online" == "1" ]] && return 0
  done
  return 1
}

detect_battery_capacity() {
  read_first_existing_file /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -n 1 || true
}

crossystem_value() {
  local key="$1"
  command -v crossystem >/dev/null 2>&1 || return 1
  crossystem "$key" 2>/dev/null | sed 's/.*= *//' | sed 's/[[:space:]]*$//'
}

wp_summary() {
  local wp=""
  wp="$(crossystem_value wpsw_cur || true)"
  case "$wp" in
    0) printf 'disabled by crossystem' ;;
    1) printf 'enabled by crossystem' ;;
    *) printf 'unknown' ;;
  esac
}

firmware_id() {
  local fwid=""
  fwid="$(crossystem_value fwid || true)"
  printf '%s' "${fwid:-unknown}"
}

uefi_runtime_available() {
  [[ -d /sys/firmware/efi/efivars ]]
}

json_get() {
  local file="$1"
  local key="$2"
  sed -nE "s/^[[:space:]]*\"$key\"[[:space:]]*:[[:space:]]*\"?([^\",}]*)\"?,?[[:space:]]*$/\\1/p" "$file" | head -n 1
}

default_manifest_url() {
  if [[ "$RELEASE_BASE_URL" == *raw.githubusercontent.com* ]]; then
    printf '%s/manifest.json' "$RELEASE_BASE_URL"
  else
    local tag="dell3189-$CHANNEL"
    printf '%s/%s/manifest.json' "$RELEASE_BASE_URL" "$tag"
  fi
}

load_manifest() {
  local local_channel_manifest="$SCRIPT_DIR/$CHANNEL.json"
  local local_manifest="$SCRIPT_DIR/manifest.json"
  local repo_channel_manifest="$SCRIPT_DIR/../releases/dell3189/$CHANNEL.json"
  local source=""

  if [[ -n "$MANIFEST_OVERRIDE" ]]; then
    source="$MANIFEST_OVERRIDE"
  elif [[ -f "$local_channel_manifest" ]]; then
    source="$local_channel_manifest"
  elif [[ -f "$local_manifest" ]]; then
    source="$local_manifest"
  elif [[ -f "$repo_channel_manifest" ]]; then
    source="$repo_channel_manifest"
  else
    source="$(default_manifest_url)"
  fi

  MANIFEST_FILE="$RUN_DIR/manifest-$CHANNEL.json"
  if is_url "$source"; then
    if try_download_file "$source" "$MANIFEST_FILE"; then
      log "Manifest loaded: $source"
    elif [[ -n "$MANIFEST_OVERRIDE" ]]; then
      fail "Unable to download manifest: $source"
    else
      log "Remote manifest unavailable; using built-in $CHANNEL metadata."
      cat >"$MANIFEST_FILE" <<EOF
{
  "device": "$DEVICE_NAME",
  "board": "$EXPECTED_BOARD",
  "version": "$ROM_VERSION",
  "channel": "$CHANNEL",
  "rom_name": "$ROM_NAME",
  "rom_url": "$RELEASE_BASE_URL/dell3189-$CHANNEL/$ROM_NAME",
  "sha256": "$ROM_SHA256",
  "size": $ROM_SIZE
}
EOF
    fi
  else
    copy_or_download "$source" "$MANIFEST_FILE"
  fi

  MANIFEST_DEVICE="$(json_get "$MANIFEST_FILE" device || true)"
  MANIFEST_BOARD="$(json_get "$MANIFEST_FILE" board || true)"
  MANIFEST_VERSION="$(json_get "$MANIFEST_FILE" version || true)"
  MANIFEST_SHA256="$(json_get "$MANIFEST_FILE" sha256 || true)"
  MANIFEST_SIZE="$(json_get "$MANIFEST_FILE" size || true)"
  MANIFEST_ROM_URL="$(json_get "$MANIFEST_FILE" rom_url || true)"
  MANIFEST_MIRROR_1="$(json_get "$MANIFEST_FILE" mirror_url_1 || true)"
  MANIFEST_MIRROR_2="$(json_get "$MANIFEST_FILE" mirror_url_2 || true)"

  MANIFEST_DEVICE="${MANIFEST_DEVICE:-$DEVICE_NAME}"
  MANIFEST_BOARD="${MANIFEST_BOARD:-$EXPECTED_BOARD}"
  MANIFEST_VERSION="${MANIFEST_VERSION:-$ROM_VERSION}"
  MANIFEST_SHA256="${MANIFEST_SHA256:-$ROM_SHA256}"
  MANIFEST_SIZE="${MANIFEST_SIZE:-$ROM_SIZE}"
  if [[ -z "$MANIFEST_ROM_URL" ]]; then
    if [[ "$RELEASE_BASE_URL" == *raw.githubusercontent.com* ]]; then
      MANIFEST_ROM_URL="$RELEASE_BASE_URL/$ROM_NAME"
    else
      MANIFEST_ROM_URL="$RELEASE_BASE_URL/dell3189-$CHANNEL/$ROM_NAME"
    fi
  fi
}

verify_device() {
  local board model alias matched="0"
  board="$(detect_board)"
  model="$(detect_model)"

  log "Detected board: ${board:-unknown}"
  log "Detected model: ${model:-unknown}"
  log "Firmware ID: $(firmware_id)"
  log "Write protect: $(wp_summary)"

  for alias in $BOARD_ALIASES; do
    if [[ "$board" == "$(normalize_board "$alias")" ]]; then
      matched="1"
    fi
  done

  [[ "$matched" == "1" ]] || fail "This installer supports only board $EXPECTED_BOARD. Detected '${board:-unknown}'."

  if [[ -n "$model" && "$model" != *"3189"* && "$model" != *"Chromebook 11"* ]]; then
    log "Model string did not clearly identify Dell Chromebook 11 3189; continuing because board check passed."
  fi
}

show_info() {
  say "${BOLD}$TOOLKIT_NAME${RESET}"
  say ""
  say "Device target:   $DEVICE_NAME"
  say "Required board:  $EXPECTED_BOARD"
  say "Detected board:  $(detect_board)"
  say "Detected model:  $(detect_model || true)"
  say "Firmware ID:     $(firmware_id)"
  say "Write protect:   $(wp_summary)"
  say "AC power:        $(detect_ac_power && printf connected || printf unknown/disconnected)"
  say "Battery:         $(detect_battery_capacity || printf unknown)%"
  say "Channel:         $CHANNEL"
  say "ROM version:     $MANIFEST_VERSION"
  say "ROM SHA256:      $MANIFEST_SHA256"
  say "Log file:        $LOG_FILE"
}

preflight_flashrom() {
  say "${BLUE}Checking flashrom access...${RESET}"
  flashrom -p "$FLASHROM_PROGRAMMER" --flash-name 2>&1 | tee -a "$LOG_FILE" || \
    fail "flashrom cannot access the SPI flash with programmer '$FLASHROM_PROGRAMMER'."

  if flashrom -p "$FLASHROM_PROGRAMMER" --wp-status >/tmp/retech-wp-status.$$ 2>&1; then
    log "flashrom write-protect status:"
    tee -a "$LOG_FILE" </tmp/retech-wp-status.$$
  else
    log "flashrom --wp-status did not complete; continuing with normal write checks."
    cat /tmp/retech-wp-status.$$ >>"$LOG_FILE" || true
  fi
  rm -f /tmp/retech-wp-status.$$
}

obtain_rom_file() {
  local local_rom="$SCRIPT_DIR/$ROM_NAME"
  local source_list=()
  local source

  if [[ -n "$ROM_OVERRIDE" ]]; then
    source_list+=("$ROM_OVERRIDE")
  elif [[ -f "$local_rom" ]]; then
    source_list+=("$local_rom")
  else
    source_list+=("$MANIFEST_ROM_URL")
    [[ -n "$MANIFEST_MIRROR_1" ]] && source_list+=("$MANIFEST_MIRROR_1")
    [[ -n "$MANIFEST_MIRROR_2" ]] && source_list+=("$MANIFEST_MIRROR_2")
  fi

  for source in "${source_list[@]}"; do
    if try_copy_or_download "$source" "$ROM_PATH"; then
      log "ROM source succeeded: $source"
      return 0
    fi
    log "ROM source failed: $source"
  done

  fail "Unable to obtain ROM from all configured sources."
}

verify_rom_file() {
  local size actual
  [[ -f "$ROM_PATH" ]] || fail "Firmware ROM not found: $ROM_PATH"
  [[ -s "$ROM_PATH" ]] || fail "Firmware ROM is empty: $ROM_PATH"

  size="$(wc -c <"$ROM_PATH" | tr -d ' ')"
  actual="$(sha256sum "$ROM_PATH" | awk '{print tolower($1)}')"

  log "ROM size: $size bytes"
  log "Expected ROM size: $MANIFEST_SIZE bytes"
  log "Expected ROM SHA256: $MANIFEST_SHA256"
  log "Actual ROM SHA256:   $actual"

  [[ "$size" == "$MANIFEST_SIZE" ]] || fail "Firmware ROM size mismatch."
  [[ "$actual" == "$MANIFEST_SHA256" ]] || fail "Firmware ROM SHA256 verification failed."
}

confirm_flash() {
  cat <<EOF | tee -a "$LOG_FILE"

${BOLD}Ready to flash firmware${RESET}

Target:       $DEVICE_NAME / $EXPECTED_BOARD
Channel:      $CHANNEL
ROM version:  $MANIFEST_VERSION
ROM file:     $ROM_PATH
Backup:       $BACKUP_FILE

This will write the verified firmware ROM to SPI flash.
It will not wipe the internal eMMC.

Keep AC power connected. Do not close the lid or power off the Chromebook.

EOF

  if [[ "$YES" == "1" ]]; then
    log "Confirmation skipped because --yes/CFT_YES=1 is set."
    return 0
  fi

  printf 'Flash %s firmware now? [Y/n]: ' "$CHANNEL" | tee -a "$LOG_FILE"
  local answer
  read -r answer
  printf '%s\n' "$answer" >>"$LOG_FILE"

  case "$answer" in
    ""|y|Y|yes|YES) return 0 ;;
    *) fail "Operator chose not to flash." ;;
  esac
}

backup_current_firmware() {
  say "${BLUE}Backing up current firmware...${RESET}"
  if ! flashrom -p "$FLASHROM_PROGRAMMER" -r "$BACKUP_FILE" 2>&1 | tee -a "$LOG_FILE"; then
    fail "flashrom failed while reading the current firmware backup."
  fi

  [[ -s "$BACKUP_FILE" ]] || fail "Firmware backup failed or produced an empty file."
  sha256sum "$BACKUP_FILE" | tee -a "$LOG_FILE"
  say "${GREEN}Backup saved:${RESET} $BACKUP_FILE"
}

flash_rom() {
  say "${YELLOW}Flashing firmware. Do not power off the device.${RESET}"
  if ! flashrom -p "$FLASHROM_PROGRAMMER" --ifd -i bios -N -w "$ROM_PATH" 2>&1 | tee -a "$LOG_FILE"; then
    fail "flashrom failed while writing. Do not reboot until recovery status is understood."
  fi

  say "${GREEN}Firmware flash completed.${RESET}"
}

clear_uefi_nvram() {
  say "${BLUE}Cleaning UEFI NVRAM state...${RESET}"
  log "Erasing SMMSTORE region using the same firmware-level approach as MrChromebox Clear UEFI NVRAM."

  if flashrom -p "$FLASHROM_PROGRAMMER" -E -i SMMSTORE --fmap 2>&1 | tee -a "$LOG_FILE"; then
    say "${GREEN}UEFI NVRAM SMMSTORE region cleared.${RESET}"
  else
    log "SMMSTORE erase did not complete. The ReTech ROM image is still built with a fresh UEFI variable store."
  fi

  if ! uefi_runtime_available; then
    log "UEFI runtime variables are not available in this boot; skipping efibootmgr cleanup."
    return 0
  fi

  if ! command -v efibootmgr >/dev/null 2>&1; then
    log "efibootmgr is not installed; skipping runtime Boot#### cleanup."
    return 0
  fi

  local entry bootnum
  while read -r entry; do
    bootnum="$(printf '%s' "$entry" | sed -nE 's/^Boot([0-9A-Fa-f]{4}).*/\1/p')"
    [[ -n "$bootnum" ]] || continue
    log "Deleting UEFI boot entry Boot$bootnum"
    efibootmgr -b "$bootnum" -B 2>&1 | tee -a "$LOG_FILE" || log "Unable to delete Boot$bootnum; continuing."
  done < <(efibootmgr 2>/dev/null | grep -E '^Boot[0-9A-Fa-f]{4}')
}

reboot_after_flash() {
  if [[ "$REBOOT_AFTER_FLASH" != "1" ]]; then
    log "Automatic reboot skipped because --no-reboot/CFT_REBOOT=0 is set."
    return 0
  fi

  say "${GREEN}Rebooting in 10 seconds...${RESET}"
  say "Press Ctrl+C now if you need to stay in this shell."
  sleep 10

  if command -v systemctl >/dev/null 2>&1; then
    systemctl reboot 2>&1 | tee -a "$LOG_FILE" || true
  fi

  reboot 2>&1 | tee -a "$LOG_FILE" || fail "Flash succeeded, but automatic reboot failed. Reboot manually."
}

restore_backup() {
  [[ -n "$RESTORE_FILE" ]] || fail "--restore requires a backup ROM file."
  [[ -f "$RESTORE_FILE" ]] || fail "Backup ROM not found: $RESTORE_FILE"

  preflight_flashrom
  ROM_PATH="$RESTORE_FILE"
  MANIFEST_SIZE="$(wc -c <"$ROM_PATH" | tr -d ' ')"
  MANIFEST_SHA256="$(sha256sum "$ROM_PATH" | awk '{print tolower($1)}')"
  confirm_flash
  flash_rom
}

post_flash_instructions() {
  cat <<EOF | tee -a "$LOG_FILE"

${GREEN}Done.${RESET}

Next steps after reboot:
  1. Confirm the ReTech splash appears.
  2. Open the boot menu and install Debian/Linux from USB.
  3. Keep this backup until the machine has passed QA:
     $BACKUP_FILE

Log:
  $LOG_FILE

EOF
}

recovery_help() {
  cat <<EOF
Recovery notes

- If the machine still boots, keep the backup and rerun this tool with:
    sudo bash dell3189.sh --restore /path/to/backup.rom

- If the machine does not boot, recovery usually requires an external SPI
  programmer and the backup ROM created before flashing.

- Do not wipe eMMC as part of this firmware recovery flow.
EOF
}

run_flash_flow() {
  verify_device
  show_info
  preflight_flashrom
  obtain_rom_file
  verify_rom_file
  confirm_flash
  backup_current_firmware
  flash_rom
  clear_uefi_nvram
  post_flash_instructions
  reboot_after_flash
}

run_backup_flow() {
  verify_device
  preflight_flashrom
  backup_current_firmware
}

menu() {
  while true; do
    say ""
    say "${BOLD}$TOOLKIT_NAME${RESET}"
    say "1) Firmware/device info"
    say "2) Backup current firmware only"
    say "3) Flash $CHANNEL firmware"
    say "4) Restore from backup"
    say "5) Recovery help"
    say "6) Quit"
    printf 'Select option [1-6]: '
    local choice
    read -r choice
    case "$choice" in
      1) show_info ;;
      2) run_backup_flow; return 0 ;;
      3) run_flash_flow; return 0 ;;
      4)
        printf 'Backup ROM path: '
        read -r RESTORE_FILE
        restore_backup
        return 0
        ;;
      5) recovery_help ;;
      6) say "No changes made."; return 0 ;;
      *) say "${YELLOW}Choose 1-6.${RESET}" ;;
    esac
  done
}

main() {
  parse_args "$@"
  setup_color
  require_root
  init_runtime
  require_commands
  load_manifest

  case "$ACTION" in
    info) verify_device; show_info ;;
    backup) run_backup_flow ;;
    restore) verify_device; restore_backup ;;
    flash) run_flash_flow ;;
    menu) menu ;;
    *) fail "Unknown action: $ACTION" ;;
  esac
}

main "$@"
