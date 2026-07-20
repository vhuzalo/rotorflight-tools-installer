#!/usr/bin/env bash
set -Eeuo pipefail

# Rotorflight Tools Installer
# Installs or updates Rotorflight Configurator, Rotorflight Blackbox,
# ExpressLRS Configurator, and Linux udev rules for flight controllers.

BASE_DIR="/opt"
APPLICATIONS_DIR="/usr/share/applications"
USER_APPLICATIONS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
RELEASE_LIMIT="${RELEASE_LIMIT:-10}"
UDEV_RULES_PATH="/etc/udev/rules.d/60-rotorflight.rules"

declare -A REPO=(
  [configurator]="rotorflight/rotorflight-configurator"
  [blackbox]="rotorflight/rotorflight-blackbox"
  [expresslrs]="ExpressLRS/ExpressLRS-Configurator"
)

declare -A APP_DIR=(
  [configurator]="rotorflight-configurator"
  [blackbox]="rotorflight-blackbox"
  [expresslrs]="expresslrs-configurator"
)

declare -A APP_NAME=(
  [configurator]="Rotorflight Configurator"
  [blackbox]="Rotorflight Blackbox"
  [expresslrs]="ExpressLRS Configurator"
)

declare -A EXEC_NAME=(
  [configurator]="rotorflight-configurator"
  [blackbox]="rotorflight-blackbox"
  [expresslrs]="expresslrs-configurator"
)

declare -A ICON_PATH=(
  [configurator]="icon/rf_icon.png"
  [blackbox]="icon/rf_icon_128.png"
  [expresslrs]="expresslrs-configurator"
)

declare -A DESKTOP_ID=(
  [configurator]="rotorflight.desktop"
  [blackbox]="rotorflight-blackbox.desktop"
  [expresslrs]="expresslrs-configurator.desktop"
)

declare -A COMMENT=(
  [configurator]="Cross-platform configuration tool for the Rotorflight flight control system"
  [blackbox]="Cross-platform blackbox analytics tool for Rotorflight flight control system"
  [expresslrs]="Cross-platform configuration tool for ExpressLRS devices"
)

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing dependency: $1"
    echo "On Manjaro/Arch, install with: sudo pacman -S --needed curl jq unzip tar"
    echo "On Ubuntu/Debian, install with: sudo apt install curl jq unzip tar"
    exit 1
  }
}

show_help() {
  cat <<'HELP'
Rotorflight Tools Installer

Installs or updates on Linux:
  - Rotorflight Configurator
  - Rotorflight Blackbox
  - ExpressLRS Configurator
  - udev rules for USB/DFU access to flight controllers

Usage:
  ./bin/rotorflight-tools-installer.sh
  RELEASE_LIMIT=20 ./bin/rotorflight-tools-installer.sh

Options:
  -h, --help    Show this help

Notes:
  - Applications are installed under /opt.
  - .desktop launchers are created for the current user and globally when possible.
  - Some steps may ask for sudo.
  - The "All" option automatically uses the latest stable version of each app.
HELP
}

parse_args() {
  case "${1:-}" in
    -h|--help)
      show_help
      exit 0
      ;;
    "")
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Use --help to see available options." >&2
      exit 2
      ;;
  esac
}

run_privileged() {
  if "$@"; then
    return 0
  fi

  if command -v sudo >/dev/null 2>&1; then
    sudo "$@"
    return
  fi

  return 1
}

api_get() {
  local repo="$1"
  curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/${repo}/releases?per_page=${RELEASE_LIMIT}"
}

select_app() {
  local choice

  echo
  echo "What do you want to install/update?"
  echo "  1) Rotorflight Configurator"
  echo "  2) Rotorflight Blackbox"
  echo "  3) ExpressLRS Configurator"
  echo "  4) Rotorflight Configurator + Blackbox + udev rules (default)"
  echo "  5) Install Rotorflight udev rules"
  echo "  6) All - latest stable version, no release prompt"
  echo "  q) Quit"
  read -rp "Choose [4 - Rotorflight Configurator + Blackbox + udev rules]: " choice
  choice="${choice:-4}"

  case "$choice" in
    1) SELECTED_APPS="configurator" ;;
    2) SELECTED_APPS="blackbox" ;;
    3) SELECTED_APPS="expresslrs" ;;
    4) SELECTED_APPS="configurator blackbox" ;;
    5) SELECTED_APPS="udev" ;;
    6) SELECTED_APPS="configurator blackbox expresslrs"; AUTO_STABLE_RELEASES=1 ;;
    q|Q) exit 0 ;;
    *) echo "Invalid option." >&2; return 1 ;;
  esac
}

install_udev_rules() {
  local tmp_rules

  tmp_rules="$(mktemp)"
  cat >"$tmp_rules" <<'RULES'
# Rotorflight / Betaflight flight controller USB access
# STM32 DFU bootloader used for firmware flashing
SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="df11", MODE="0666", TAG+="uaccess"

# STM32 virtual COM port
SUBSYSTEM=="tty", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="5740", MODE="0666", TAG+="uaccess"

# Common USB serial bridges used by flight controllers
SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", MODE="0666", TAG+="uaccess"
SUBSYSTEM=="tty", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="7523", MODE="0666", TAG+="uaccess"
SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6015", MODE="0666", TAG+="uaccess"
RULES

  echo
  echo "Installing udev rules to ${UDEV_RULES_PATH}..."
  run_privileged mkdir -p "$(dirname "$UDEV_RULES_PATH")"
  run_privileged cp "$tmp_rules" "$UDEV_RULES_PATH"
  run_privileged chmod 644 "$UDEV_RULES_PATH"
  rm -f "$tmp_rules"

  if command -v udevadm >/dev/null 2>&1; then
    run_privileged udevadm control --reload-rules
    run_privileged udevadm trigger
    echo "udev rules reloaded."
  else
    echo "Warning: udevadm not found; reboot the computer to load the rules."
  fi

  echo "Unplug and reconnect the flight controller before flashing firmware."
}

asset_jq_filter() {
  local app="$1"
  case "$app" in
    configurator) echo 'linux_x86_64\.tar\.xz$' ;;
    blackbox) echo 'linux64\.zip$' ;;
    expresslrs) echo 'expresslrs-configurator-[0-9][^/]*\.zip$' ;;
    *) echo "Unknown app: $app" >&2; exit 1 ;;
  esac
}

release_rows() {
  local app="$1"
  local repo="${REPO[$app]}"
  local releases_json filter

  echo >&2
  echo "Fetching ${APP_NAME[$app]} releases..." >&2
  releases_json="$(api_get "$repo")"
  filter="$(asset_jq_filter "$app")"

  jq -r --argjson limit "$RELEASE_LIMIT" --arg filter "$filter" '
    .[:$limit]
    | to_entries[]
    | .value as $release
    | ($release.assets[] | select(.name | test($filter))) as $asset
    | [
        (.key + 1),
        $release.tag_name,
        ($release.name // ""),
        ($release.published_at // ""),
        (if $release.prerelease then "pre-release" else "stable" end),
        $asset.name,
        $asset.browser_download_url
      ]
    | @tsv
  ' <<<"$releases_json"
}

select_latest_stable_release() {
  local app="$1"
  local rows stable_row

  rows="$(release_rows "$app")"

  if [[ -z "$rows" ]]; then
    echo "No compatible Linux asset found for ${APP_NAME[$app]}." >&2
    return 1
  fi

  stable_row="$(awk -F '\t' '$5 == "stable" { print; exit }' <<<"$rows")"
  if [[ -z "$stable_row" ]]; then
    echo "No stable release with a compatible Linux asset found for ${APP_NAME[$app]}." >&2
    return 1
  fi

  SELECTED_RELEASE="$stable_row"
  echo "Automatically selected: $(cut -f2 <<<"$SELECTED_RELEASE") ($(cut -f6 <<<"$SELECTED_RELEASE"))"
}

select_release() {
  local app="$1"
  local rows count choice

  rows="$(release_rows "$app")"

  if [[ -z "$rows" ]]; then
    echo "No compatible Linux asset found for ${APP_NAME[$app]}." >&2
    return 1
  fi

  count="$(wc -l <<<"$rows" | tr -d ' ')"
  echo
  echo "Available releases:"
  awk -F '\t' '{printf "  %2d) %-24s %-12s %s\n      %s\n", NR, $2, $5, substr($4, 1, 10), $6}' <<<"$rows"
  echo "   q) Cancel"

  while true; do
    read -rp "Choose the release for ${APP_NAME[$app]} [1]: " choice
    choice="${choice:-1}"
    case "$choice" in
      q|Q) return 1 ;;
      ''|*[!0-9]*) echo "Enter a number between 1 and $count, or q to cancel." ;;
      *)
        if (( choice >= 1 && choice <= count )); then
          SELECTED_RELEASE="$(sed -n "${choice}p" <<<"$rows")"
          return 0
        fi
        echo "Enter a number between 1 and $count, or q to cancel."
        ;;
    esac
  done
}

download_size() {
  local url="$1"
  curl -sSIL -L "$url" \
    | awk 'BEGIN { IGNORECASE = 1 } /^content-length:/ { gsub("\r", "", $2); size = $2 } END { print size }'
}

human_bytes() {
  local bytes="$1"
  awk -v bytes="$bytes" '
    function human(value, unit) {
      split("B KiB MiB GiB", unit)
      while (value >= 1024 && unit[2] != "") {
        value /= 1024
        for (i = 1; i < length(unit); i++) unit[i] = unit[i + 1]
        delete unit[length(unit)]
      }
      if (unit[1] == "B") printf "%d %s", value, unit[1]
      else printf "%.1f %s", value, unit[1]
    }
    BEGIN { human(bytes) }
  '
}

spaced_bar() {
  local text="$1"
  local output=""
  local i

  for ((i = 0; i < ${#text}; i++)); do
    if (( i > 0 )); then
      output+=" "
    fi
    output+="${text:i:1}"
  done

  printf '%s' "$output"
}

render_candy_progress() {
  local file="$1"
  local total="$2"
  local frame="$3"
  local current percent filled empty bar_width term_width status trail ahead raw_bar pretty_bar

  current="$(stat -c '%s' "$file" 2>/dev/null || echo 0)"
  term_width="$(tput cols 2>/dev/null || echo 80)"
  bar_width=$(((term_width - 38) / 2))
  (( bar_width < 10 )) && bar_width=10
  (( bar_width > 25 )) && bar_width=25

  if [[ "$total" =~ ^[0-9]+$ && "$total" -gt 0 && "$current" -le "$total" ]]; then
    percent=$((current * 100 / total))
    (( percent > 100 )) && percent=100
    filled=$((percent * bar_width / 100))
    (( filled >= bar_width )) && filled=$((bar_width - 1))
    empty=$((bar_width - filled - 1))
    trail="$(printf '%*s' "$filled" '' | tr ' ' '-')"
    ahead="$(printf '%*s' "$empty" '' | tr ' ' '0')"
    raw_bar="${trail}${frame}${ahead}"
    pretty_bar="$(spaced_bar "$raw_bar")"
    status="$(human_bytes "$current")/$(human_bytes "$total")"
    printf '\r[%s] %3d%% %s' "$pretty_bar" "$percent" "$status"
  else
    filled=$((current / 1048576 % bar_width))
    trail="$(printf '%*s' "$filled" '' | tr ' ' '0')"
    ahead="$(printf '%*s' "$((bar_width - filled - 1))" '' | tr ' ' '0')"
    raw_bar="${trail}${frame}${ahead}"
    pretty_bar="$(spaced_bar "$raw_bar")"
    status="$(human_bytes "$current")"
    printf '\r[%s] %s' "$pretty_bar" "$status"
  fi
}

download_with_candy() {
  local url="$1"
  local output="$2"
  local total pid status frame_index frame
  local frames=(C c)

  total="$(download_size "$url" || true)"
  rm -f "$output"

  curl -fL --silent --show-error "$url" -o "$output" &
  pid=$!
  frame_index=0

  while kill -0 "$pid" 2>/dev/null; do
    frame="${frames[$((frame_index % ${#frames[@]}))]}"
    render_candy_progress "$output" "$total" "$frame"
    frame_index=$((frame_index + 1))
    sleep 0.12
  done

  wait "$pid"
  status=$?
  if [[ "$status" -eq 0 ]]; then
    render_candy_progress "$output" "$total" "C"
    printf '\n'
  else
    printf '\n'
  fi

  return "$status"
}

extract_archive() {
  local archive="$1"
  local target="$2"

  mkdir -p "$target"
  case "$archive" in
    *.tar.xz) tar -xJf "$archive" -C "$target" ;;
    *.zip) unzip -q "$archive" -d "$target" ;;
    *)
      echo "Unsupported archive format: $archive" >&2
      return 1
      ;;
  esac
}

find_payload_dir() {
  local root="$1"
  local executable="$2"
  local found

  found="$(find "$root" -type f -name "$executable" -perm -u+x -print -quit)"
  if [[ -z "$found" ]]; then
    found="$(find "$root" -type f -name "$executable" -print -quit)"
  fi

  if [[ -z "$found" ]]; then
    return 1
  fi

  dirname "$found"
}

install_extracted_shared_assets() {
  local extract_dir="$1"
  local icons_dir="${extract_dir}/usr/share/icons"

  if [[ -d "$icons_dir" ]]; then
    run_privileged mkdir -p /usr/share/icons
    run_privileged cp -a "${icons_dir}/." /usr/share/icons/
  fi

  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    if [[ -w /usr/share/icons/hicolor ]]; then
      gtk-update-icon-cache -q /usr/share/icons/hicolor >/dev/null 2>&1 || true
    elif command -v sudo >/dev/null 2>&1; then
      sudo gtk-update-icon-cache -q /usr/share/icons/hicolor >/dev/null 2>&1 || true
    fi
  fi
}

configure_electron_sandbox() {
  local app="$1"
  local install_dir="${BASE_DIR}/${APP_DIR[$app]}"
  local sandbox_path="${install_dir}/chrome-sandbox"

  [[ "$app" == "expresslrs" ]] || return 0

  if [[ ! -f "$sandbox_path" ]]; then
    echo "Warning: Electron sandbox not found at ${sandbox_path}." >&2
    return 0
  fi

  echo "Configuring the Electron sandbox..."
  run_privileged chown root:root "$sandbox_path"
  run_privileged chmod 4755 "$sandbox_path"

  if [[ "$(stat -c '%U:%G %a' "$sandbox_path")" != "root:root 4755" ]]; then
    echo "Could not configure the Electron sandbox at ${sandbox_path}." >&2
    return 1
  fi
}

write_desktop_file() {
  local app="$1"
  local dest="$2"
  local install_dir="${BASE_DIR}/${APP_DIR[$app]}"
  local exec_path="${install_dir}/${EXEC_NAME[$app]}"
  local icon="${ICON_PATH[$app]}"
  local icon_path

  mkdir -p "$(dirname "$dest")"
  if [[ "$icon" == /* ]]; then
    icon_path="$icon"
  elif [[ "$icon" == */* ]]; then
    icon_path="${install_dir}/${icon}"
  else
    icon_path="$icon"
  fi

  {
    echo "[Desktop Entry]"
    echo "Name=${APP_NAME[$app]}"
    echo "Comment=${COMMENT[$app]}"
    echo "Exec=${exec_path}"
    echo "Icon=${icon_path}"
    echo "Terminal=false"
    echo "Type=Application"
    echo "Categories=Utility;"
    if [[ "$app" == "blackbox" ]]; then
      echo "MimeType=application/x-blackboxlog;"
    fi
  } >"$dest"
}

install_desktop_files() {
  local app="$1"
  local app_dir="${BASE_DIR}/${APP_DIR[$app]}"
  local desktop_name="${DESKTOP_ID[$app]}"
  local temp_desktop

  temp_desktop="$(mktemp)"
  write_desktop_file "$app" "$temp_desktop"

  run_privileged cp "$temp_desktop" "${app_dir}/${EXEC_NAME[$app]}.desktop"
  run_privileged chmod 644 "${app_dir}/${EXEC_NAME[$app]}.desktop"

  mkdir -p "$USER_APPLICATIONS_DIR"
  cp "$temp_desktop" "${USER_APPLICATIONS_DIR}/${desktop_name}"
  chmod 644 "${USER_APPLICATIONS_DIR}/${desktop_name}"

  if [[ -w "$APPLICATIONS_DIR" ]]; then
    cp "$temp_desktop" "${APPLICATIONS_DIR}/${desktop_name}"
    chmod 644 "${APPLICATIONS_DIR}/${desktop_name}"
  elif command -v sudo >/dev/null 2>&1; then
    sudo cp "$temp_desktop" "${APPLICATIONS_DIR}/${desktop_name}" || true
    sudo chmod 644 "${APPLICATIONS_DIR}/${desktop_name}" || true
  else
    echo "Warning: could not update ${APPLICATIONS_DIR}/${desktop_name}; run with sudo if you want a global launcher."
  fi

  rm -f "$temp_desktop"

  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$USER_APPLICATIONS_DIR" >/dev/null 2>&1 || true
    if [[ -w "$APPLICATIONS_DIR" ]]; then
      update-desktop-database "$APPLICATIONS_DIR" >/dev/null 2>&1 || true
    elif command -v sudo >/dev/null 2>&1; then
      sudo update-desktop-database "$APPLICATIONS_DIR" >/dev/null 2>&1 || true
    fi
  fi
}

install_app() {
  local app="$1"
  local tag asset_name url tmp archive extract_dir payload_dir install_dir backup_dir stamp

  if [[ "${AUTO_STABLE_RELEASES:-0}" -eq 1 ]]; then
    select_latest_stable_release "$app" || return 0
  else
    select_release "$app" || return 0
  fi

  tag="$(cut -f2 <<<"$SELECTED_RELEASE")"
  asset_name="$(cut -f6 <<<"$SELECTED_RELEASE")"
  url="$(cut -f7 <<<"$SELECTED_RELEASE")"

  tmp="$(mktemp -d)"
  archive="${tmp}/${asset_name}"
  extract_dir="${tmp}/extract"
  install_dir="${BASE_DIR}/${APP_DIR[$app]}"
  stamp="$(date +%Y%m%d-%H%M%S)"
  backup_dir="${install_dir}.bak-${stamp}"

  echo
  echo "Downloading ${asset_name}..."
  download_with_candy "$url" "$archive"

  echo "Extracting..."
  extract_archive "$archive" "$extract_dir"

  payload_dir="$(find_payload_dir "$extract_dir" "${EXEC_NAME[$app]}")" || {
    echo "Could not find executable ${EXEC_NAME[$app]} inside the package." >&2
    rm -rf "$tmp"
    return 1
  }

  chmod +x "${payload_dir}/${EXEC_NAME[$app]}" || true

  echo "Installing to ${install_dir}..."
  if [[ -e "$install_dir" ]]; then
    run_privileged mv "$install_dir" "$backup_dir"
    echo "Backup created at ${backup_dir}"
  fi

  run_privileged mkdir -p "$BASE_DIR"
  run_privileged mv "$payload_dir" "$install_dir"
  run_privileged chmod +x "${install_dir}/${EXEC_NAME[$app]}"
  configure_electron_sandbox "$app"

  install_extracted_shared_assets "$extract_dir"
  install_desktop_files "$app"
  rm -rf "$tmp"

  echo "${APP_NAME[$app]} installed/updated to ${tag}."
}

main() {
  parse_args "$@"

  need_cmd curl
  need_cmd jq
  need_cmd tar
  need_cmd unzip
  need_cmd find
  need_cmd awk

  echo "Rotorflight Tools Installer"
  echo "Base installation directory: ${BASE_DIR}"

  local app
  until select_app; do
    true
  done

  for app in $SELECTED_APPS; do
    case "$app" in
      configurator)
        install_app "$app"
        install_udev_rules
        ;;
      udev)
        install_udev_rules
        ;;
      *)
        install_app "$app"
        ;;
    esac
  done

  echo
  echo "Done."
}

main "$@"
