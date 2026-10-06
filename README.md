# Grid

A small native macOS window manager in the spirit of Divvy. It lives in the menu bar,
and a global shortcut brings up a grid you can drag across (or hit a single key) to snap
the focused window into place, instantly with no animation.

## Use

- **⌥Space** (configurable) opens the grid over the focused window's display.
- **Drag** across cells to choose an area; release to apply. A single click picks one cell.
- **Press a shortcut key** (e.g. `F` full screen, `C` center, arrows for halves,
  `Q W A S` for quarters) to snap without the mouse. Plain keys need no modifier.
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
identity in your keychain, else the first **Apple Development** one (`just signing` shows which;
override with `GRID_SIGN_IDENTITY="…"`). A stable signature is what lets macOS keep Grid's
Accessibility access across rebuilds. `just build` stops with an error if no certificate is found.

To install a certificate without Xcode:

1. Keychain Access → Certificate Assistant → *Request a Certificate From a Certificate Authority*
   → enter your email → *Saved to disk*.
2. developer.apple.com → Certificates → **+** → *Apple Development* (or *Developer ID Application*)
   → upload the request → download the `.cer` and double-click it.
3. If `just signing` still finds nothing, install Apple's intermediate certificate from
   apple.com/certificateauthority ("Worldwide Developer Relations – G3" for Apple Development,
   "Developer ID – G2" for Developer ID).

## Layout

- `Sources/GridCore`: pure, tested logic: key combos, config model, screen geometry.
- `Sources/Grid`: the app: menu bar item, Carbon global hotkey, overlay panel, AX window control, SwiftUI settings and onboarding.
