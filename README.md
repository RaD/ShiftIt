# ShiftItGo

Go-based macOS window manager derived from ShiftIt.

ShiftItGo replaces the legacy Objective‑C ShiftIt app with a Go core and a thin Cocoa bridge.
Original project:
```
https://github.com/fikovnik/ShiftIt
```
It listens for global hotkeys and moves/resizes the focused window according to predefined
actions (left/right halves, thirds, corners, maximize, move to next screen, etc). The menu bar
icon shows the active shortcuts and provides clickable actions, so you can trigger the same
window moves from the menu without using the keyboard.

The app reads defaults from `resources/ShiftIt-defaults.plist` and registers only the supported
actions it finds there. You can override resource paths with `SHIFTIT_ICON_PATH` and
`SHIFTIT_DEFAULTS_PATH` if you want to test custom assets or configs.

## Build

```bash
make bundle
```

## Install

```bash
make install
```

### System Setup

1. First launch:
   ```bash
   open /Applications/ShiftItGo.app
   ```
2. Grant Accessibility permissions:
   System Settings → Privacy & Security → Accessibility → enable for ShiftItGo.
3. Optional auto‑start:
   System Settings → General → Login Items → add `/Applications/ShiftItGo.app`.

## Uninstall

```bash
make uninstall
```

## Run (with debug)

```bash
make run
```

## Notes

- Requires Accessibility permission in System Settings → Privacy & Security → Accessibility.
- The app bundle is built to `build/ShiftItGo.app`.
