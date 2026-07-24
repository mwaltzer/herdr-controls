# Herdr Menu-Bar App — Architecture and Product Plan

Working name: **Herdr Controls**. This documents how the
`home-manager/packages/sketchy-controls` prototype evolves into a standalone
macOS menu-bar app for Herdr session awareness and switching, with SketchyBar
kept as an optional thin adapter.

## Current state (post Tranche 1)

One SPM package, five targets:

| Target | Role |
| --- | --- |
| `HerdrCore` | Foundation-only product core: session contracts, discovery, navigation, connection lifecycle, preferences. No AppKit/SwiftUI/Carbon. Fully covered by checks. |
| `SketchyControlsCore` | Panel IPC adapter contract: `PanelCommand` parsing + unix-datagram-socket client/server used by external callers (SketchyBar today). |
| `SketchyControls` | The app shell: menu-bar `NSStatusItem`, `NSPanel` UI, SwiftUI views, Settings window, live `PreferencesController`, system services (audio/network/power/calendar/VPN), global hotkey, launchd-run `LSUIElement` binary. Consumes both cores. |
| `SketchyControlsCLI` | `sketchy-controls` binary; sends `PanelCommand`s over the socket. What SketchyBar click scripts call. |

`SketchyControlsCoreChecks` is the test runner (plain assertions, no XCTest —
chosen because the nix `checkPhase` runs a bare executable). It covers both
core modules and runs on every `nix build` of the package.

### HerdrCore boundary

- **Contracts** (`Contracts.swift`): versioned decoders for the two session
  sources — the local `herdr` CLI envelopes (`herdr workspace list`,
  `herdr agent list`; `HerdrContract.localVersion`) and the
  `herdr-tailnet-sessions` aggregated host array
  (`HerdrContract.tailnetVersion`). Decoders throw typed
  `HerdrContractError`s and tolerate unknown fields, so newer Herdr releases
  don't break older app builds. Bump a version only when a decoder stops
  accepting a previously valid payload.
- **Discovery** (`Discovery.swift`): `HerdrSessionDiscovery` produces a
  `HerdrSnapshot` through an injectable `HerdrCommandRunning` process runner.
  Local-CLI failure degrades to a tailnet-only snapshot carrying the failure
  reason (`HerdrLocalStatus.unavailable`); remote failure degrades to an empty
  host list. `snapshot.available` preserves the prototype's semantics.
- **Navigation** (`Navigation.swift`): pure keyboard-navigation model —
  ordered target list (workspaces interleaved with their agents, then hosts
  with their remote agents), location/kind scoping, wrap-around selection
  movement, post-refresh and post-scope-change normalization. Target keys
  double as UI row identifiers.
- **Lifecycle** (`Lifecycle.swift`): `HerdrConnectionState`, deterministic
  `RetryPolicy` backoffs, the `HerdrDiscoveryHealth` reducer (folds each
  snapshot into a connection state plus the next retry delay; the bounded
  `panelRetry` policy runs 1→2→4→8→16 s then hands off to the cadence timer),
  and `HerdrPanelStatus.issue` — the pure classifier of why the selected
  (location, kind) list is empty: loading, local CLI unavailable with its
  cause, tailnet discovery off, or scope-specific emptiness (including
  agents-list emptiness while workspaces exist).
- **Environment** (`Environment.swift`): `HerdrEnvironmentReport` — first-run
  readiness over the herdr CLI (required) and tailnet helpers (optional), with
  executability injected so it stays checkable.
- **Preferences** (`Preferences.swift`): versioned `HerdrPreferences`
  (tool paths, terminal app, tailnet-discovery toggle, panel hotkey as a
  semantic `HotKeySpec`, refresh cadence, default panel location/kind, hidden
  tailnet hosts) behind a `HerdrPreferencesStore` protocol with a JSON file
  store at `~/Library/Application Support/HerdrControls/preferences.json`.
  Missing fields backfill defaults; unknown enum raw values from newer
  versions degrade per-field instead of discarding the file; corrupt files
  fall back to defaults rather than blocking launch. Validation lives in core:
  `HotKeySpec.validationError` (modifier required, key-code range),
  `isValidHostName` (same charset the tailnet scripts enforce; invalid
  hidden-host entries are dropped on load), `refreshInterval` clamped to
  5–3600 s, and the `HerdrTerminal` catalog (Ghostty, kitty, WezTerm,
  Alacritty).

### Adapter posture

SketchyBar is already a thin adapter: items call
`sketchy-controls toggle <panel>` via `config/sketchybar/plugins/panel_click.sh`,
and the badge plugin (`plugins/herdr.sh`) shells the same discovery commands.
The socket + `PanelCommand` schema in `SketchyControlsCore` is the adapter
contract; any future bar/launcher integrates the same way. Herdr session
opening on remote hosts goes through `~/.local/bin/herdr-open-tailnet-session`
(source: `home-manager/config/herdr/open-tailnet-session.sh`). The configured
terminal travels as a third argv element (never through a shell); the script
honors only exact known terminal names — each mapped to a fixed launch argv —
and logs + falls back to Ghostty for anything else, so preference tampering
cannot inject arguments.

## Target architecture

```
                    ┌────────────────────────────┐
   SketchyBar ────► │ SketchyControlsCLI (socket)│──┐
   (optional        └────────────────────────────┘  │  PanelCommand v1
    adapter)                                        ▼
┌──────────────┐    ┌───────────────────────────────────────────┐
│ menu bar     │    │ App shell (menu-bar item, panels, settings)│
│ NSStatusItem │◄───┤  SwiftUI views + PanelController           │
└──────────────┘    └───────────────┬───────────────────────────┘
                                    │ types only, no shelling in UI
                    ┌───────────────▼───────────────┐
                    │ HerdrCore                     │
                    │ contracts · discovery ·       │
                    │ navigation · lifecycle ·      │
                    │ preferences · (diagnostics)   │
                    └───────────────┬───────────────┘
                                    │ HerdrCommandRunning
                     herdr CLI · herdr-tailnet-sessions · ssh
```

Rules that keep the boundary honest:

- `HerdrCore` never imports AppKit/SwiftUI/Carbon and never runs a process
  directly — everything external goes through `HerdrCommandRunning` or a
  store protocol, so it stays checkable without a live environment.
- The app shell owns presentation and OS integration only. New behavior lands
  in `HerdrCore` first, with checks, then gets a UI.
- External surfaces (`PanelCommand`, the two session contracts, the
  preferences file) are versioned; changes must stay
  decode-tolerant-of-unknowns in both directions.

## Product requirements → where they land

| Requirement | Home | Status |
| --- | --- | --- |
| Versioned local/tailnet session contracts | `HerdrCore/Contracts.swift` | Done (v1, typed errors, unknown-field tolerant, human-readable causes) |
| Connection errors / retry | `Lifecycle.swift` reducer + Herdr panel issue views | Done: cause-specific empty states, live retry countdown, Retry Now / Check Again / Open Settings actions |
| Onboarding | `Environment.swift` + `OnboardingWindow.swift` | Done: first-run welcome with component detection, shortcut/tailnet/SketchyBar explainers; completion persisted; reopenable from Settings |
| Preferences | `HerdrCore/Preferences.swift` + `PreferencesController` | Done: live-updating, observable, saved on every change |
| Terminal configuration | Settings picker → `openRemote` argv → script | Done (Ghostty/kitty/WezTerm/Alacritty; unknown values fall back to Ghostty) |
| Shortcut configuration | `HotKeySpec` + Settings recorder | Done: recorder with validation; shell re-registers live |
| Refresh cadence / default panel scope / hidden hosts | Preferences + Settings window | Done; cadence consumed by app-shell timer, hidden hosts filtered in core discovery |
| Settings UI | `SettingsWindow.swift` / `SettingsViews.swift` | Done (entry: Control Center row + Herdr panel gear); onboarding still open |
| Security / privacy | See below | Ongoing |
| Accessibility / multi-display / reduced motion | App shell | Partial: Reduce Motion honored in panel animations, native anchoring/status-item hotkey landed; VoiceOver sweep still open |
| Diagnostics | `HerdrCore/Diagnostics.swift` + Settings → Support | Done: copy-diagnostics report (hostnames/session titles omitted) |
| Signing / notarization / updates / distribution | Packaging | Phase 4 |

### Security and privacy stance

- No network access from the app itself; all remote reach is via the user's
  `ssh` (BatchMode, keys only) through the tailnet helper scripts, which
  validate host/pane arguments against strict character classes.
- The IPC socket is per-user (`$TMPDIR/sketchy-controls-$UID.sock`, mode 600).
  Commands are display-only actions (show/dismiss panels); no secrets transit
  the socket. Keep it that way — anything privileged must not be reachable
  from the socket.
- Calendar access uses the standard EventKit prompt (usage strings in the
  Info.plist). Preferences contain paths and UI choices only, never secrets.
- Logs (`~/Library/Logs/sketchy-controls*.log`) may contain hostnames; keep
  session titles out of logs when diagnostics land.

## Phased plan

**Phase 1 — core extraction (this tranche, done).** `HerdrCore` exists, is
checked, and the app consumes it with behavior identical to the prototype.
Preferences file read at launch (hotkey, tool paths, tailnet toggle).

**Phase 2 — standalone menu-bar product (in progress).**
- Done — `NSStatusItem` in the app (`StatusItemController.swift`) with
  app-shell lifecycle in `main.swift`: live preference observation re-registers
  the global hotkey and drives a session-refresh timer at the configured
  cadence.
- Done — Settings window (`SettingsWindow.swift`, `SettingsViews.swift`)
  bound to the live `PreferencesController`: hotkey recorder with validation,
  terminal picker, tailnet discovery toggle, per-host hide/show list (offline
  hidden hosts stay listed for unhiding), refresh cadence, default panel
  location/kind. Every change persists immediately; save failures surface in
  the window. Opened from the Control Center "Settings" row or the Herdr
  panel's gear button.
- Done — configured terminal threaded through
  `HerdrService.openRemote` → `open-tailnet-session.sh` as a plain argv
  element with exact-name matching in the script (no shell interpolation).
- Done — reliability surfacing: every Herdr snapshot folds through
  `HerdrDiscoveryHealth`; a failed local CLI shows its cause with a live
  "Retrying in Ns" countdown (bounded backoff, then the cadence timer takes
  over) and a Retry Now action; tailnet-off, no-sessions, and empty-agents
  states each get a precise message and matching action.
- Done — first-run onboarding (`OnboardingWindow.swift`): detects the herdr
  CLI and tailnet helpers via `HerdrEnvironmentReport`, explains the shortcut,
  tailnet discovery (SSH, own keys), and the optional SketchyBar adapter
  (auto-detected); "Get Started" persists `onboardingCompleted`, and the
  window reopens from Settings → Support.

**Phase 3 — polish and trust.**
- Accessibility: VoiceOver labels on rows/badges, full keyboard operation
  parity, respect `accessibilityDisplayShouldReduceMotion` in the
  panel morph animations.
- Multi-display: anchor panels to the screen of the invoking status item /
  cursor instead of `NSScreen.main` in the hotkey path.
- Diagnostics: an in-app "copy diagnostics" report (versions, contract
  versions, last discovery errors, tool paths) with redacted hostnames.

**Phase 4 — distribution (release engineering landed; credentials pending).**

Product identity is now single-sourced:

- `VERSION` in the package root is the semantic version. It feeds the nix
  derivation and `release/package.sh`; the app reads it back at runtime via
  `CFBundleShortVersionString` (diagnostics shows "development" only for bare
  `swift run` builds).
- `release/Info.plist.in` is the one bundle definition — name **Herdr
  Controls**, identifier `com.mwaltzer.herdr-controls` — consumed by both the
  nix install and release packaging, so dogfood and release bundles always
  agree. `release/HerdrControls.entitlements` declares the hardened-runtime
  surface (calendars only; deliberately unsandboxed because the app spawns
  the herdr CLI, helper scripts, and ssh).

Release packaging (no credentials required):

```sh
cd home-manager/packages/sketchy-controls
./release/package.sh            # build + assemble + zip + sha256 + verify
./release/package.sh verify     # re-check an existing dist/
./release/package.sh clean      # remove dist/ (output dir is guard-railed)
```

Unsigned archives are deterministic — identical inputs give identical zips
(sorted entries, normalized modes, `SOURCE_DATE_EPOCH` mtimes) — so a release
can be reproduced and compared by hash. Signed artifacts are *not* byte-stable
(CMS signatures embed timestamps); verify those with `codesign`/`spctl`, not
by hash.

Signing/notarization hooks are environment-driven and never run by default:

```sh
# One-time: xcrun notarytool store-credentials herdr-notary --apple-id … --team-id …
HC_SIGN_IDENTITY="Developer ID Application: <name> (<team>)" \
HC_NOTARY_PROFILE=herdr-notary \
./release/package.sh

# Independent verification of a signed artifact:
codesign --verify --deep --strict "dist/Herdr Controls.app"
spctl -a -t exec -vv "dist/Herdr Controls.app"
shasum -a 256 -c dist/HerdrControls-<version>-arm64.zip.sha256
```

Update/distribution strategy, in order:

1. **Dogfood (now)**: nix/Home Manager builds the same bundle from the same
   plist template; launchd runs it. Updates arrive via `home-manager switch`.
2. **Manual releases (next)**: tag → `./release/package.sh` on a signing
   machine → upload zip + `.sha256` to a GitHub Release once the repo split
   happens. Users verify the checksum; notarization makes Gatekeeper quiet.
   No in-app updater yet — the app is launchd-managed for dogfood, and
   `CFBundleVersion` (override with `HC_BUILD_VERSION`) stays monotonic.
3. **Sparkle (later, if the audience grows)**: requires an appcast URL,
   `SUFeedURL` in the plist template, and EdDSA keys — deferred until the
   standalone repo exists so the feed has a stable home. Homebrew cask
   follows the first notarized GitHub release.

Still open for Phase 4: repo extraction, an app icon (`CFBundleIconFile` is
intentionally absent), universal (arm64+x86_64) builds, and a verified
copyright holder for `NSHumanReadableCopyright` (omitted until confirmed).

## Verification

```sh
cd home-manager/packages/sketchy-controls
swift build && swift run SketchyControlsCoreChecks   # fast loop
swift build -c release && .build/release/SketchyControlsCoreChecks  # what nix runs
```

`nix build` of the package (via `home-manager build`) runs the same checks in
its `checkPhase`.
