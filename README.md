# Grid

A small native macOS window manager in the spirit of Divvy. It lives in the menu bar,
and a global shortcut brings up a grid you can drag across (or hit a single key) to snap
the focused window into place, instantly with no animation.

## Use

- **⌥Space** (configurable) opens the grid over the focused window's display.
- **Drag** across cells to choose an area; release to apply. A single click picks one cell.
- **Press a shortcut key** to snap without the mouse. Plain keys need no modifier. Defaults:
  `Space` full screen, `G` center, `E` / `D` / `C` top-left / left half / bottom-left,
  `I` / `K` / `,` top-right / right half / bottom-right.
- **Tab / ⇧Tab** moves the window to the next / previous display.
- **Press the launch shortcut again** to cycle displays too (or close the grid; see Settings).
- **Esc** or clicking elsewhere closes it.

Settings (menu bar icon → Settings…) cover the launch shortcut, grid size (1–10 × 1–10),
repeat-press behavior, launch at login, and your saved shortcuts. Each saved shortcut
remembers the grid it was drawn on, so changing the grid size never breaks it.

## Build

Needs only the Xcode Command Line Tools (Swift 6) and [`just`](https://github.com/casey/just), with no Xcode project.

```sh
just              # list recipes
just install      # build, copy to /Applications, launch
just run          # build and launch from build/ without installing
just test         # unit tests (geometry, models)
just snapshot     # render settings, overlay and onboarding screens to build/snapshots
just reset-onboarding / reset-permissions / reset-all
```

## Permissions

The first launch opens a short setup guide (reopen it any time from the menu bar via
**Setup Guide…**). It covers:

1. **Accessibility** (required). This is how macOS lets Grid move and resize other apps'
   windows. The guide opens the right System Settings pane, watches for the switch to flip,
   and comes back to the front on its own. The global shortcut itself needs no permission.
2. **Launch at login** (optional). If macOS asks you to approve it in Login Items, the guide links there.
3. **Try it.** A live checklist that ticks off as you open the grid and snap a window.

## Signing

Builds are signed with your Apple developer certificate: the first **Developer ID Application**
identity in your keychain, else the first **Apple Development** one. If your Apple ID belongs to
several teams, `GRID_TEAM_ID` (set at the top of the Justfile) restricts it to one team's
certificates. `just signing` shows which certificate will be used. A stable signature is what lets
macOS keep Grid's Accessibility access across updates.

To get a certificate: Xcode → Settings → Accounts → select the team → **Manage Certificates…**
→ **+** → **Apple Development**.

With Xcode installed, builds are universal (Apple silicon + Intel) and run on macOS 14 and later.

## Install on other Macs

Releases are published to GitHub, and every Mac installs the same signed build:

```sh
just release 1.0     # on the build Mac: build, sign, push, publish the GitHub release
just update          # on any Mac with a checkout: install the latest release
```

On a Mac without a checkout:

```sh
curl -fsSL https://raw.githubusercontent.com/kurtbuilds/grid/master/scripts/install-latest.sh | bash
```

Builds are signed but not notarized, which is fine for your own Macs: files downloaded with
`curl` aren't quarantined, so Gatekeeper doesn't get involved. A copy downloaded in a browser would
be blocked; clear the flag with `xattr -dr com.apple.quarantine /Applications/Grid.app`.
Accessibility access is granted once per Mac and then survives updates.

## Layout

- `Sources/GridCore`: pure, tested logic: key combos, config model, screen geometry.
- `Sources/Grid`: the app: menu bar item, Carbon global hotkey, overlay panel, AX window control, SwiftUI settings and onboarding.
