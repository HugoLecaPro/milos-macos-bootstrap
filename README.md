# MILOS macOS Bootstrap

Public bootstrap entrypoint for installing and updating the private MILOS macOS
app with a single terminal command.

## Who This Repo Is For

Use this repo in one of two ways:

- **Colleague / operator**: you want the MILOS app installed or updated on your
  Mac, but you are not publishing releases yourself.
- **Developer / releaser**: you are preparing a new release candidate or stable
  release in the private MILOS app repo and need to know which command your
  colleagues should run afterward.

## Colleague / Operator Guide

Before first install, make sure you have been granted GitHub access to both
private repositories and have accepted those invitations in GitHub:

- `HugoLecaPro/MILOS-ESP-Serial-Python`
- `HugoLecaPro/MILOS-ESP-Serial-Firmware`

### First install or update to the latest approved release

Run this command:

```bash
curl -fsSL https://raw.githubusercontent.com/HugoLecaPro/milos-macos-bootstrap/main/install-milos-macos.sh | bash
```

Use this when you want the current official release.

### Install or update to a specific release candidate

If the developer asks you to test a specific version, run the same installer
but pin the requested release tag:

```bash
curl -fsSL https://raw.githubusercontent.com/HugoLecaPro/milos-macos-bootstrap/main/install-milos-macos.sh | bash -s -- --version issue-8-rc2
```

Replace `issue-8-rc2` with the exact tag the developer gives you.

### What happens when you run the installer

The installer:

- downloads the selected private MILOS release from GitHub
- installs `MILOS.app` into `~/Applications`
- creates or updates the operator workspace at `~/Documents/MILOS`
- clones or updates the managed firmware checkout at
  `~/Documents/MILOS/firmware/MILO-ESP-Serial`
- writes runtime config to
  `~/Library/Application Support/MILOS/config.json`
- launches the app automatically on first install

If the app is already installed and you want the installer to reopen it after an
update, add `--launch`:

```bash
curl -fsSL https://raw.githubusercontent.com/HugoLecaPro/milos-macos-bootstrap/main/install-milos-macos.sh | bash -s -- --launch
```

### GitHub access token: what it is, why it is needed, and when you will be asked

The MILOS app release and firmware repo are private GitHub repositories. Because
of that, the installer needs a GitHub credential the first time it runs on a
machine.

That credential is a **GitHub fine-grained personal access token (PAT)**. It is
only used so the installer can:

- download the private MILOS release assets
- clone or update the private firmware repository

On first run, the installer prompts:

```text
GitHub PAT:
```

Paste your token there. The installer stores it in your macOS Keychain under
`MILOS_GITHUB_PAT`, so you should normally only be asked once per machine. You
will be asked again only if the token is deleted from Keychain, revoked,
expired, or replaced.

### How to create the PAT

In GitHub:

1. Open `Settings`
2. Open `Developer settings`
3. Open `Personal access tokens`
4. Create a **Fine-grained personal access token**
5. Set repository access to **Only select repositories**
6. Select these two repositories:
   - `HugoLecaPro/MILOS-ESP-Serial-Python`
   - `HugoLecaPro/MILOS-ESP-Serial-Firmware`
7. Set repository permissions to:
   - `Contents: Read-only`
   - `Metadata: Read-only`

If you are a colleague, that is the only GitHub setup you need.

### Canonical update rule

When new code should be available, follow this rule:

- if you were told to use a specific test version, rerun the installer with
  `--version <tag>`
- if you were told the latest approved release is ready, rerun the installer
  without `--version`

You do not need to manually remove the old app first.

## Developer / Releaser Guide

The full developer-side packaging and release workflow lives in the private MILOS
app repo documentation:

- private repo path: `docs/installation/Private_macOS_Release.md`

The short release-candidate checklist is:

1. Work from the intended feature branch in the private app repo.
2. Commit and push all source changes first.
3. Pin the exact firmware commit you want the release to use.
4. Build release artifacts:

   ```bash
   ./scripts/build_milos_macos_release.sh \
     --version <release-tag> \
     --firmware-revision <firmware-commit>
   ```

5. Publish the GitHub pre-release from that branch:

   ```bash
   gh release create <release-tag> \
     dist/release/MILOS.app.zip \
     dist/release/milos-release.json \
     --target <branch-name> \
     --prerelease \
     --title "<release name>" \
     --notes "<release notes>"
   ```

6. Tell colleagues exactly which command to run:
   - for an RC: the pinned `--version <release-tag>` command
   - for an approved latest release: the unpinned latest command

### Canonical release rule

When you want colleagues to use **new code that is not yet merged or not yet the
official default**, publish a new **release candidate tag** and tell them to use
the pinned installer command.

When you want colleagues to use the **current approved release**, publish that
release in the private app repo and tell them to rerun the unpinned installer
command.

Do not overwrite or mutate an existing release candidate. If you find a release
bug, publish a new tag such as `issue-8-rc2`, `issue-8-rc3`, and so on.

## Optional Flags

```bash
install-milos-macos.sh [--version <tag>] [--launch]
```

- `--version <tag>` installs a specific GitHub Release tag
- `--launch` launches the app after an update as well as after a first install
