# MILOS macOS Bootstrap

Public bootstrap entrypoint for the private MILOS macOS app.

## Install latest release

```bash
curl -fsSL https://raw.githubusercontent.com/HugoLecaPro/milos-macos-bootstrap/main/install-milos-macos.sh | bash
```

## Install a pinned release

```bash
curl -fsSL https://raw.githubusercontent.com/HugoLecaPro/milos-macos-bootstrap/main/install-milos-macos.sh | bash -s -- --version v1.2.3
```

## What the installer does

- Downloads the latest or requested private MILOS GitHub Release
- Installs `MILOS.app` into `~/Applications`
- Creates the managed operator workspace at `~/Documents/MILOS`
- Clones or updates the managed firmware checkout at `~/Documents/MILOS/firmware/MILO-ESP-Serial`
- Writes runtime config to `~/Library/Application Support/MILOS/config.json`
- Removes quarantine from the installed app bundle
- Launches the app automatically on first install

## Authentication

The app and firmware repositories stay private. On first run, the installer prompts for a GitHub fine-grained personal access token and stores it in the macOS Keychain under `MILOS_GITHUB_PAT`.

The token needs read access to:

- `HugoLecaPro/MILOS-ESP-Serial-Python`
- the private MILOS firmware repository

Later installs and updates reuse the stored token.

## Update behavior

- Running the same command again updates the installed app in place
- Firmware is reset to the exact revision declared by the selected app release manifest
- Workspace calibration profiles are mirrored back into the managed firmware checkout so `uploadfs` continues to work

## Optional flags

```bash
install-milos-macos.sh [--version <tag>] [--launch]
```

- `--version <tag>` installs a specific GitHub Release tag
- `--launch` launches the app after an update as well as after a first install
