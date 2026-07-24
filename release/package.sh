#!/usr/bin/env bash
# Deterministic release packaging for Herdr Controls.
#
#   release/package.sh [package|verify|clean]
#
# `package` (default) builds the release binary, assembles "Herdr Controls.app",
# and produces a zip + sha256 under dist/. UNSIGNED archives are byte-stable:
# identical inputs yield identical zips (normalized permissions/mtimes, sorted
# entries, SOURCE_DATE_EPOCH). Signed/notarized artifacts are NOT byte-stable —
# CMS signatures embed signing time and a secure timestamp — so reproduce-and-
# compare verification applies to the unsigned archive only; signed artifacts
# are verified via codesign/spctl instead. Signing and notarization run ONLY
# when their inputs are present in the environment — this script never prompts
# and never embeds credentials:
#
#   HC_SIGN_IDENTITY   Developer ID Application identity (codesign -s value).
#                      Enables hardened-runtime signing with the entitlements
#                      file next to this script.
#   HC_NOTARY_PROFILE  notarytool keychain profile name (from
#                      `xcrun notarytool store-credentials`). Enables
#                      submission + stapling; requires HC_SIGN_IDENTITY.
#   HC_BUILD_VERSION   CFBundleVersion override (defaults to VERSION).
#   SOURCE_DATE_EPOCH  Timestamp for archive determinism (fixed default).
#   HC_OUT_DIR         Output directory (default: <package>/dist).
#
# `verify` re-checks the assembled bundle: plist lint, structure, and — when
# signed — codesign/spctl verification.
set -euo pipefail

package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
release_dir="$package_root/release"
version="$(tr -d '[:space:]' < "$package_root/VERSION")"
build_version="${HC_BUILD_VERSION:-$version}"
out_dir="${HC_OUT_DIR:-$package_root/dist}"
arch="$(uname -m)"
epoch="${SOURCE_DATE_EPOCH:-1753228800}" # 2025-07-23T00:00:00Z, fixed for determinism

log() { printf '==> %s\n' "$1"; }
die() { echo "error: $1" >&2; exit 1; }

# out_dir is caller-controlled and this script deletes inside it, so refuse
# anything that is not a dedicated artifact directory: canonicalize, then
# reject /, $HOME, the package root, their ancestors, and any existing
# non-empty directory that doesn't already hold our artifacts.
canonicalize_out_dir() {
  local base
  base="$(basename "$out_dir")"
  [[ -n "$base" && "$base" != "/" && "$base" != "." && "$base" != ".." ]] \
    || die "HC_OUT_DIR must name a dedicated directory (got '$out_dir')"
  mkdir -p "$out_dir"
  out_dir="$(cd "$out_dir" && pwd -P)" || die "cannot resolve HC_OUT_DIR '$out_dir'"
  [[ "$out_dir" != "/" ]] || die "refusing to use / as the output directory"
  [[ "$out_dir" != "$HOME" ]] || die "refusing to use \$HOME as the output directory"
  [[ "$out_dir" != "$package_root" ]] || die "refusing to use the package root as the output directory"
  case "$package_root/" in
    "$out_dir"/*) die "refusing HC_OUT_DIR '$out_dir': it contains the package root" ;;
  esac
  case "$HOME/" in
    "$out_dir"/*) die "refusing HC_OUT_DIR '$out_dir': it contains \$HOME" ;;
  esac
  if [[ -n "$(ls -A "$out_dir" 2>/dev/null)" ]]; then
    [[ -e "$out_dir/Herdr Controls.app" || -n "$(find "$out_dir" -maxdepth 1 -name 'HerdrControls-*.zip*' -print -quit)" ]] \
      || die "refusing HC_OUT_DIR '$out_dir': non-empty and not a Herdr Controls artifact directory"
  fi
}
canonicalize_out_dir
app_dir="$out_dir/Herdr Controls.app"
zip_path="$out_dir/HerdrControls-$version-$arch.zip"

build() {
  log "swift build -c release ($arch)"
  (cd "$package_root" && swift build -c release >/dev/null)
}

assemble() {
  local bin_path
  bin_path="$(cd "$package_root" && swift build -c release --show-bin-path)/SketchyControls"
  [[ -x "$bin_path" ]] || { echo "error: release binary missing at $bin_path" >&2; exit 1; }

  log "assembling $app_dir"
  rm -rf "$app_dir"
  mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
  install -m 755 "$bin_path" "$app_dir/Contents/MacOS/SketchyControls"
  install -m 644 "$package_root/Sources/SketchyControls/Resources/herdr-mask.svg" \
                 "$package_root/Sources/SketchyControls/Resources/tailscale-icon.svg" \
                 "$app_dir/Contents/Resources/"
  sed -e "s/@SHORT_VERSION@/$version/g" -e "s/@BUILD_VERSION@/$build_version/g" \
    "$release_dir/Info.plist.in" > "$app_dir/Contents/Info.plist"
  printf 'APPL????' > "$app_dir/Contents/PkgInfo"
  plutil -lint "$app_dir/Contents/Info.plist" >/dev/null
}

sign() {
  if [[ -z "${HC_SIGN_IDENTITY:-}" ]]; then
    log "HC_SIGN_IDENTITY unset — leaving the bundle unsigned"
    return 0
  fi
  log "codesigning with '$HC_SIGN_IDENTITY' (hardened runtime)"
  codesign --force --timestamp --options runtime \
    --entitlements "$release_dir/HerdrControls.entitlements" \
    --sign "$HC_SIGN_IDENTITY" "$app_dir"
}

archive() {
  log "writing deterministic archive $zip_path"
  rm -f "$zip_path" "$zip_path.sha256"
  # Normalize permissions and mtimes so identical inputs produce identical
  # zips; -X drops platform extra fields (uid/gid, native timestamps).
  find "$app_dir" -type d -exec chmod 755 {} +
  find "$app_dir" -type f -exec chmod 644 {} +
  chmod 755 "$app_dir/Contents/MacOS/SketchyControls"
  local stamp
  # GNU (-d @epoch) and BSD (-r epoch) date syntaxes differ; try both.
  stamp="$(TZ=UTC date -u -d "@$epoch" +%Y%m%d%H%M.%S 2>/dev/null \
    || TZ=UTC date -u -r "$epoch" +%Y%m%d%H%M.%S)"
  find "$app_dir" -exec touch -t "$stamp" {} +
  (cd "$out_dir" && find "Herdr Controls.app" | LC_ALL=C sort \
    | TZ=UTC zip -X -q "$(basename "$zip_path")" -@)
  (cd "$out_dir" && shasum -a 256 "$(basename "$zip_path")" > "$(basename "$zip_path").sha256")
  log "sha256: $(cut -d' ' -f1 "$zip_path.sha256")"
}

notarize() {
  if [[ -z "${HC_NOTARY_PROFILE:-}" ]]; then
    log "HC_NOTARY_PROFILE unset — skipping notarization"
    return 0
  fi
  [[ -n "${HC_SIGN_IDENTITY:-}" ]] || { echo "error: notarization requires HC_SIGN_IDENTITY" >&2; exit 1; }
  log "submitting to notary service (profile $HC_NOTARY_PROFILE)"
  xcrun notarytool submit "$zip_path" --keychain-profile "$HC_NOTARY_PROFILE" --wait
  xcrun stapler staple "$app_dir"
  # Stapling changes the bundle: rebuild the archive so the shipped zip
  # contains the ticket.
  archive
}

verify() {
  [[ -d "$app_dir" ]] || { echo "error: run 'package' first ($app_dir missing)" >&2; exit 1; }
  log "verifying bundle structure"
  plutil -lint "$app_dir/Contents/Info.plist" >/dev/null
  [[ -x "$app_dir/Contents/MacOS/SketchyControls" ]]
  [[ -f "$app_dir/Contents/Resources/herdr-mask.svg" ]]
  local plist_version
  plist_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_dir/Contents/Info.plist")"
  [[ "$plist_version" == "$version" ]] || { echo "error: plist version $plist_version != VERSION $version" >&2; exit 1; }
  if [[ -f "$zip_path.sha256" ]]; then
    (cd "$out_dir" && shasum -a 256 -c "$(basename "$zip_path").sha256" >/dev/null)
    log "archive checksum verified"
  fi
  if [[ -d "$app_dir/Contents/_CodeSignature" ]]; then
    log "verifying code signature"
    codesign --verify --deep --strict "$app_dir"
    spctl -a -t exec -vv "$app_dir" || log "spctl rejected (expected until notarized)"
  else
    log "bundle is unsigned (ok for dogfood/pre-signing)"
  fi
  log "verify passed"
}

case "${1:-package}" in
  package)
    mkdir -p "$out_dir"
    build
    assemble
    sign
    archive
    notarize
    verify
    ;;
  verify) verify ;;
  clean) rm -rf "$out_dir"; log "removed $out_dir" ;;
  *) echo "usage: package.sh [package|verify|clean]" >&2; exit 64 ;;
esac
