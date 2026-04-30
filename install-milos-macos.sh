#!/usr/bin/env bash

set -euo pipefail

APP_REPO="${MILOS_APP_REPO:-HugoLecaPro/MILOS-ESP-Serial-Python}"
MANIFEST_ASSET_NAME="${MILOS_MANIFEST_ASSET_NAME:-milos-release.json}"
KEYCHAIN_SERVICE="${MILOS_GITHUB_PAT_SERVICE:-MILOS_GITHUB_PAT}"
APP_INSTALL_ROOT="${MILOS_APP_INSTALL_ROOT:-$HOME/Applications}"
WORKSPACE_ROOT="${MILOS_WORKSPACE_ROOT:-$HOME/Documents/MILOS}"
CONFIG_PATH="${MILOS_CONFIG_PATH:-$HOME/Library/Application Support/MILOS/config.json}"
VERSION=""
FORCE_LAUNCH=0

usage() {
  cat <<'EOF'
Usage: install-milos-macos.sh [--version <tag>] [--launch]

Downloads the private MILOS macOS release, installs MILOS.app into
~/Applications, provisions ~/Documents/MILOS, syncs the managed firmware
checkout, writes runtime config, and launches the app on first install.
EOF
}

log() {
  printf '%s\n' "$*"
}

tty_log() {
  printf '%s\n' "$*" >/dev/tty
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --launch)
      FORCE_LAUNCH=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

require_cmd curl
require_cmd base64
require_cmd ditto
require_cmd git
require_cmd security
require_cmd xattr
require_cmd osascript
require_cmd plutil
require_cmd mktemp
require_cmd open

json_asset_api_url() {
  local json_file="$1"
  local asset_name="$2"
  /usr/bin/osascript -l JavaScript - "$json_file" "$asset_name" <<'EOF'
ObjC.import('Foundation');
function run(argv) {
  const jsonPath = argv[0];
  const assetName = argv[1];
  const jsonText = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(
    $(jsonPath),
    $.NSUTF8StringEncoding,
    null
  ));
  const payload = JSON.parse(jsonText);
  const asset = (payload.assets || []).find((entry) => entry.name === assetName);
  if (!asset || !asset.url) {
    throw new Error(`Asset not found in release metadata: ${assetName}`);
  }
  return asset.url;
}
EOF
}

json_string() {
  local json_file="$1"
  local key="$2"
  plutil -extract "$key" raw -expect string -o - "$json_file"
}

release_api_url() {
  if [ -n "$VERSION" ]; then
    printf 'https://api.github.com/repos/%s/releases/tags/%s\n' "$APP_REPO" "$VERSION"
  else
    printf 'https://api.github.com/repos/%s/releases/latest\n' "$APP_REPO"
  fi
}

prompt_for_token() {
  tty_log "A GitHub fine-grained PAT is required to access private MILOS release assets."
  tty_log "Grant read access to repository contents for:"
  tty_log "  - $APP_REPO"
  tty_log "  - the private MILOS firmware repo"
  printf 'GitHub PAT: ' >/dev/tty
  local token
  IFS= read -r -s token </dev/tty
  printf '\n' >/dev/tty
  [ -n "$token" ] || fail "Empty GitHub token."
  security add-generic-password -U -a "$USER" -s "$KEYCHAIN_SERVICE" -w "$token" >/dev/null
  printf '%s' "$token"
}

github_token() {
  if security find-generic-password -a "$USER" -s "$KEYCHAIN_SERVICE" -w >/tmp/milos_github_pat.$$ 2>/dev/null; then
    cat /tmp/milos_github_pat.$$
    rm -f /tmp/milos_github_pat.$$
    return 0
  fi
  prompt_for_token
}

download_json() {
  local token="$1"
  local url="$2"
  local output="$3"
  curl -fsSL \
    -H "Authorization: Bearer $token" \
    -H "Accept: application/vnd.github+json" \
    "$url" \
    -o "$output"
}

download_asset() {
  local token="$1"
  local asset_api_url="$2"
  local output="$3"
  curl -fsSL \
    -H "Authorization: Bearer $token" \
    -H "Accept: application/octet-stream" \
    "$asset_api_url" \
    -o "$output"
}

git_auth_header() {
  local token="$1"
  printf 'x-access-token:%s' "$token" | base64 | tr -d '\n'
}

git_with_auth() {
  local token="$1"
  shift
  git -c http.extraHeader="Authorization: Basic $(git_auth_header "$token")" "$@"
}

write_runtime_config() {
  local firmware_root="$1"
  local config_dir
  config_dir="$(dirname "$CONFIG_PATH")"
  mkdir -p "$config_dir"
  cat >"$CONFIG_PATH" <<EOF
{
  "workspace_root": "$WORKSPACE_ROOT",
  "firmware_root": "$firmware_root"
}
EOF
}

mirror_workspace_calibrations() {
  local firmware_root="$1"
  local workspace_profiles_dir="$WORKSPACE_ROOT/calibration/profiles"
  local firmware_calibration_dir="$firmware_root/data/calibrations"
  mkdir -p "$firmware_calibration_dir"
  if [ -d "$workspace_profiles_dir" ]; then
    find "$workspace_profiles_dir" -maxdepth 1 -type f -name '*.json' -print0 | while IFS= read -r -d '' profile; do
      cp "$profile" "$firmware_calibration_dir/$(basename "$profile")"
    done
  fi
}

sync_firmware_repo() {
  local token="$1"
  local repo_url="$2"
  local revision="$3"
  local firmware_root="$WORKSPACE_ROOT/firmware/MILO-ESP-Serial"

  mkdir -p "$(dirname "$firmware_root")"

  if [ -d "$firmware_root/.git" ]; then
    log "Updating managed firmware checkout..." >&2
    if ! git_with_auth "$token" -C "$firmware_root" fetch --tags --force origin; then
      fail "Failed to fetch managed firmware checkout."
    fi
  else
    log "Cloning managed firmware checkout..." >&2
    if ! git_with_auth "$token" clone "$repo_url" "$firmware_root"; then
      fail "Failed to clone managed firmware checkout."
    fi
  fi

  git -C "$firmware_root" config advice.detachedHead false
  if ! git -C "$firmware_root" checkout --force "$revision"; then
    fail "Failed to checkout firmware revision: $revision"
  fi
  mirror_workspace_calibrations "$firmware_root"
  printf '%s' "$firmware_root"
}

install_app_bundle() {
  local zip_path="$1"
  local bundle_name="$2"
  mkdir -p "$APP_INSTALL_ROOT"

  local extract_dir
  extract_dir="$(mktemp -d)"
  ditto -xk "$zip_path" "$extract_dir"

  local extracted_bundle="$extract_dir/$bundle_name"
  [ -d "$extracted_bundle" ] || fail "Expected bundle not found in archive: $bundle_name"

  local install_path="$APP_INSTALL_ROOT/$bundle_name"
  rm -rf "$install_path"
  mv "$extracted_bundle" "$install_path"
  xattr -dr com.apple.quarantine "$install_path" >/dev/null 2>&1 || true

  rm -rf "$extract_dir"
  printf '%s' "$install_path"
}

should_launch() {
  local first_install="$1"
  if [ "$FORCE_LAUNCH" -eq 1 ]; then
    return 0
  fi
  [ "$first_install" -eq 1 ]
}

main() {
  local token
  token="$(github_token)"

  local temp_dir
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "${temp_dir:-}"' EXIT

  local release_json="$temp_dir/release.json"
  log "Fetching release metadata..."
  download_json "$token" "$(release_api_url)" "$release_json"

  local manifest_asset_url="$(
    json_asset_api_url "$release_json" "$MANIFEST_ASSET_NAME"
  )"
  local manifest_path="$temp_dir/$MANIFEST_ASSET_NAME"
  log "Downloading release manifest..."
  download_asset "$token" "$manifest_asset_url" "$manifest_path"

  local app_asset_name app_bundle_name firmware_repo_url firmware_revision
  app_asset_name="$(json_string "$manifest_path" "app_asset_name")"
  app_bundle_name="$(json_string "$manifest_path" "app_bundle_name")"
  firmware_repo_url="$(json_string "$manifest_path" "firmware_repo_url")"
  firmware_revision="$(json_string "$manifest_path" "firmware_revision")"

  local app_asset_url="$(
    json_asset_api_url "$release_json" "$app_asset_name"
  )"
  local app_zip="$temp_dir/$app_asset_name"
  log "Downloading packaged app..."
  download_asset "$token" "$app_asset_url" "$app_zip"

  mkdir -p "$WORKSPACE_ROOT"
  local first_install=0
  if [ ! -d "$APP_INSTALL_ROOT/$app_bundle_name" ]; then
    first_install=1
  fi

  local app_install_path
  app_install_path="$(install_app_bundle "$app_zip" "$app_bundle_name")"
  log "Installed app to $app_install_path"

  local firmware_root
  firmware_root="$(sync_firmware_repo "$token" "$firmware_repo_url" "$firmware_revision")"
  log "Managed firmware checkout ready at $firmware_root"

  write_runtime_config "$firmware_root"
  log "Wrote runtime config to $CONFIG_PATH"

  if should_launch "$first_install"; then
    log "Launching $app_bundle_name..."
    open "$app_install_path"
  else
    log "Install/update complete. Launch skipped."
  fi
}

main "$@"
