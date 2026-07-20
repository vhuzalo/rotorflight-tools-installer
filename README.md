# Rotorflight Tools Installer

Interactive Linux installer/updater for common Rotorflight tools.

The script downloads official releases, installs applications under `/opt`, creates `.desktop` launchers, and installs `udev` rules for USB/DFU access to flight controllers.

## Installed Tools

- Rotorflight Configurator
- Rotorflight Blackbox
- ExpressLRS Configurator
- HELI-X 11
- `udev` rules for firmware flashing and common USB serial ports

## Supported Systems

Tested on Manjaro Linux.

The script should work on other Linux distributions with `bash`, `curl`, `jq`, `tar`, `unzip`, `find`, `awk`, `sudo`, and `udev`, but that still needs validation.

## Installation

Clone or download this repository and run:

```bash
chmod +x bin/rotorflight-tools-installer.sh
sudo ./bin/rotorflight-tools-installer.sh
```

Show help:

```bash
./bin/rotorflight-tools-installer.sh --help
```

## Dependencies

On Manjaro/Arch:

```bash
sudo pacman -S --needed curl jq unzip tar
```

On Ubuntu/Debian:

```bash
sudo apt install curl jq unzip tar
```

## Menu

```text
1) Rotorflight Configurator
2) Rotorflight Blackbox
3) ExpressLRS Configurator
4) Rotorflight Configurator + Blackbox + udev rules (default)
5) Install Rotorflight udev rules
6) HELI-X 11
7) All - latest stable version, no release prompt
```

Options `1`, `2`, `3`, and `4` let you choose a release from the list returned by GitHub.

Option `6` downloads and installs HELI-X from its official website. Option `7` installs every tool using the latest stable releases.

## What The Script Does

- fetches official releases from GitHub;
- downloads the compatible Linux package;
- extracts the archive;
- installs the application under `/opt`;
- creates a backup of the previous installation before replacing it;
- creates `.desktop` launchers;
- installs `udev` rules to `/etc/udev/rules.d/60-rotorflight.rules`;
- downloads HELI-X from `https://www.heli-x.info/2675/HELI-X11.tar.gz` and keeps its directory writable for in-app updates;
- reloads rules with `udevadm` when available.

## Udev Rules

The `udev` rules allow the user to access flight controllers in DFU/USB mode without running the configurator as root.

After installing the rules:

1. Close the configurator.
2. Unplug the flight controller.
3. Plug it back in.
4. If permission errors continue, restart the session or reboot the computer.

## Variables

`RELEASE_LIMIT` controls how many recent releases are queried from each repository:

```bash
RELEASE_LIMIT=20 ./bin/rotorflight-tools-installer.sh
```

The default value is `10`.

`HELIX_ARCHIVE` uses a local HELI-X package instead of downloading it:

```bash
HELIX_ARCHIVE=/path/to/HELI-X11.tar.gz ./bin/rotorflight-tools-installer.sh
```

## Warnings

- The script may ask for `sudo` to write under `/opt`, `/usr/share/applications`, `/usr/share/icons`, and `/etc/udev/rules.d`.
- Do not run Electron/Chromium applications as root to work around USB permission issues. Fix the `udev` rules instead.
- Review the script before running it, especially on distributions other than Manjaro.

## License

MIT. See [LICENSE](LICENSE).
