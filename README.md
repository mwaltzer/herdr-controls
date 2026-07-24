# Herdr Controls

Herdr Controls is a native macOS menu-bar app for discovering and opening
Herdr workspaces and agents on the current Mac or across a Tailnet.

It provides:

- a native menu-bar picker and global shortcut;
- local and Tailnet session discovery;
- keyboard-first workspace and agent navigation;
- configurable terminal, refresh, scope, and host preferences;
- onboarding, bounded retry behavior, diagnostics, and accessibility support;
- a versioned local IPC adapter for optional integrations such as SketchyBar.
- native deep links for Shortcuts and launchers;
- provider-neutral jj/Git metadata through an optional, allowlisted companion.

## Native links

Herdr Controls registers these macOS links:

- `herdr-controls://show`
- `herdr-controls://settings`
- `herdr-controls://workspace/<workspace-id>`
- `herdr-controls://agent/<pane-id>`
- `herdr-controls://remote/<tailnet-host>/<pane-id>`

They work from Shortcuts, Raycast, Alfred, shell scripts (`open URL`), and any
other macOS surface that opens URLs. IDs are passed directly as process
arguments; no shell interpolation is used.

## VCS companion

The optional [Herdr companion](Companion/herdr-plugin.toml) detects jj first
and Git second, then reports display-only workspace metadata through Herdr's
native metadata API:

- `vcs_provider`: `jj` or `git`
- `vcs_ref`: bookmark, branch, or revision
- `vcs_change`: jj change ID or Git commit
- `vcs_dirty`: `true` or `false`

The app ignores every other token. This is deliberately an allowlisted data
contract, not a general third-party plugin execution surface.

Run `Companion/scripts/report-vcs-metadata.sh` to refresh metadata. Herdr
expires it after two minutes, so a scheduler may safely run it once per minute.

The app uses macOS semantic colors and materials by default, so its appearance
tracks the current system release, light/dark mode, accent, and accessibility
settings. Set `HERDR_CONTROLS_THEME=catppuccin-mocha` before launch to use the
optional Catppuccin Mocha palette.

## Development

```sh
swift build
swift run SketchyControlsCoreChecks
swift build -c release
.build/release/SketchyControlsCoreChecks
```

The Nix package and release archive share `VERSION` and
`release/Info.plist.in`:

```sh
nix build
./release/package.sh
./release/package.sh verify
```

The release script produces an unsigned deterministic archive by default.
Developer ID signing and notarization run only when their documented
environment inputs are supplied.

See [the architecture and product plan](documentation/architecture.md) for
contracts, security boundaries, and release status.
