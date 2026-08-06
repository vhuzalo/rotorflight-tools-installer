# Rotorflight Tools Installer

Interactive Linux and Windows installer/updater for common Rotorflight tools.

The installers download official releases and provide native integration for each
system: `/opt`, `.desktop` launchers, and `udev` rules on Linux; per-user portable
apps, Windows shortcuts, and official `.exe` installers on Windows.

## Installed Tools

- Rotorflight Configurator
- Rotorflight Blackbox
- ExpressLRS Configurator
- [Blackbox Lab](https://github.com/hillbilly1975/Blackbox_Lab)
- Rotorflight Radio Updater for installing Lua scripts on EdgeTX/OpenTX radios
- HELI-X 11
- `udev` rules for firmware flashing and common USB serial ports

## Supported Systems

The Bash version is tested on Manjaro Linux. The PowerShell version targets
Windows 10 and 11 x64 and still needs validation on a real Windows installation.

The script should work on other Linux distributions with `bash`, `curl`, `jq`, `tar`, `unzip`, `find`, `awk`, `sudo`, and `udev`, but that still needs validation.

## Installation

### Linux

Clone or download this repository and run:

```bash
chmod +x bin/rotorflight-tools-installer.sh
sudo ./bin/rotorflight-tools-installer.sh
```

Show help:

```bash
./bin/rotorflight-tools-installer.sh --help
```

### Windows

Open PowerShell in the repository directory and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\bin\rotorflight-tools-installer.ps1
```

Show help:

```powershell
powershell -ExecutionPolicy Bypass -File .\bin\rotorflight-tools-installer.ps1 -Help
```

The Windows version downloads official x64 packages, installs portable apps under
`%LOCALAPPDATA%\Programs\Rotorflight Tools`, creates Desktop and Start Menu
shortcuts, and starts the official installer when an application is distributed
as an `.exe`. It does not need administrator privileges unless an application's
official installer requests them.

## Dependencies

### Linux

On Manjaro/Arch:

```bash
sudo pacman -S --needed curl jq unzip tar
```

On Ubuntu/Debian:

```bash
sudo apt install curl jq unzip tar
```

### Windows

- Windows PowerShell 5.1 or PowerShell 7
- Windows 10 or 11 x64 (HELI-X also supports Windows ARM64)

No extra command-line dependencies are required.

## Menu

The Linux menu includes the following options:

```text
1) Rotorflight Configurator
2) Rotorflight Blackbox
3) ExpressLRS Configurator
4) Rotorflight Configurator + Blackbox + udev rules (default)
5) Install Rotorflight udev rules
6) HELI-X 11
7) Rotorflight Radio Updater (EdgeTX/OpenTX)
8) Blackbox Lab
9) All - latest stable version, no release prompt
```

Options `1`, `2`, `3`, `4`, `7`, and `8` let you choose a release from the list returned by GitHub.

Option `6` downloads and installs HELI-X from its official website. Option `9` installs every tool using the latest stable releases.

The Windows menu mirrors these choices. Since Windows does not use `udev`, its
option `5` shows USB/DFU driver guidance instead of installing rules.

## What The Script Does

On Linux, the Bash script:

- fetches official releases from GitHub;
- downloads the compatible Linux package;
- extracts the archive;
- installs the application under `/opt`;
- selects the updater package matching Linux x86-64 or ARM64 automatically;
- installs the Blackbox Lab Linux x86-64 portable package;
- creates a backup of the previous installation before replacing it;
- creates `.desktop` launchers;
- installs `udev` rules to `/etc/udev/rules.d/60-rotorflight.rules`;
- downloads HELI-X from `https://www.heli-x.info/2675/HELI-X11.tar.gz` and keeps its directory writable for in-app updates;
- installs the official Rotorflight radio updater, which syncs `SCRIPTS` and `WIDGETS` to a mounted EdgeTX/OpenTX SD card;
- reloads rules with `udevadm` when available.

On Windows, the PowerShell script:

- fetches releases through the GitHub API and selects Windows x64 assets;
- installs Configurator, Blackbox Lab, and Radio Updater as portable apps;
- backs up an existing portable installation before replacing it;
- creates Desktop and Start Menu shortcuts for portable apps;
- runs the official Blackbox, ExpressLRS, and HELI-X installers;
- selects the HELI-X x64 or ARM64 installer automatically;
- supports choosing a release or installing all latest stable releases.

## Udev Rules

The `udev` rules allow the user to access flight controllers in DFU/USB mode without running the configurator as root.

This section applies only to Linux. Windows uses USB/DFU drivers rather than
`udev` rules; the Windows menu includes driver guidance.

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

On Windows, the equivalent options are PowerShell parameters:

```powershell
.\bin\rotorflight-tools-installer.ps1 -ReleaseLimit 20
.\bin\rotorflight-tools-installer.ps1 -HelixInstaller C:\Downloads\setupHeli-X11_win64.exe
.\bin\rotorflight-tools-installer.ps1 -InstallRoot D:\Apps\Rotorflight
```

## Warnings

- The script may ask for `sudo` to write under `/opt`, `/usr/share/applications`, `/usr/share/icons`, and `/etc/udev/rules.d`.
- Do not run Electron/Chromium applications as root to work around USB permission issues. Fix the `udev` rules instead.
- Review the script before running it, especially on distributions other than Manjaro.

## License

MIT. See [LICENSE](LICENSE).
