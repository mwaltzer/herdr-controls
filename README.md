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
