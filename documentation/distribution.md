# Standalone distribution

Nix is a supported dogfood path, not an end-user requirement. Public releases
are ordinary Developer ID-signed and Apple-notarized macOS applications.

## User installation

1. Download the DMG matching the Mac:
   - Apple silicon: `HerdrControls-<version>-arm64.dmg`
   - Intel: `HerdrControls-<version>-x86_64.dmg`
2. Open it and drag **Herdr Controls** to **Applications**.
3. Launch the app. The welcome window checks for the Herdr CLI and explains
   optional Tailnet discovery.

The app contains its Tailnet/VCS helper, Herdr companion plugin, icons, and
macOS integrations. It does not require Nix, Home Manager, Homebrew, `jq`, or
SketchyBar. Herdr itself is required. Tailscale and jj/Git are used only when
their corresponding features are enabled.

The app links its bundled, fixed-contract VCS companion after it is launched
from an Applications directory. It never installs or executes arbitrary
third-party plugins.

## Uninstallation

Quit Herdr Controls and move it from Applications to Trash. To remove the
optional integration state as well:

```sh
herdr plugin unlink dev.herdr.controls-vcs
rm -rf "$HOME/Library/Application Support/HerdrControls"
rm -rf "$HOME/Library/Caches/HerdrControls"
```

The last two commands remove preferences and cache data. They are not required
to remove the application.

## Cutting a release

Set `VERSION`, merge to `main`, then push the matching tag:

```sh
git tag "v$(tr -d '[:space:]' < VERSION)"
git push origin "v$(tr -d '[:space:]' < VERSION)"
```

The release workflow builds Apple-silicon and Intel artifacts independently,
imports the Developer ID certificate into a temporary keychain, signs every
executable with the hardened runtime, submits the ZIP to Apple's notary
service, staples the app, creates ZIP and drag-to-Applications DMG containers,
checksums them, and publishes a GitHub Release.

Repository secrets:

- `CERTIFICATE_P12_BASE64`
- `CERTIFICATE_PASSWORD`
- `KEYCHAIN_PASSWORD`
- `HC_SIGN_IDENTITY`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_PASSWORD`

`HC_SIGN_IDENTITY` is the full `Developer ID Application: …` identity.
`APPLE_APP_PASSWORD` is an app-specific password for notarization.

For a local signed build, configure a `notarytool` keychain profile and run:

```sh
HC_SIGN_IDENTITY="Developer ID Application: …" \
HC_NOTARY_PROFILE=herdr-notary \
./release/package.sh package
```

Apple requires Developer ID signing, hardened runtime, secure timestamps, and
notarization for direct distribution. The workflow uses `notarytool`, not the
retired `altool`.
