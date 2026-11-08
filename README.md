# Pullie

A macOS menu bar app that pulls windows to the screen you're on.

Pullie puts an icon in the menu bar of every display. Click it to see every app that has open windows,
with each window listed underneath. The menu acts on the display whose icon you clicked:

- Click an **app** to move all of its windows to that display.
- Click a **window** to move just that window.

A checkmark marks windows that are already on that display. Windows keep their relative position, and a
window too large for the new display is shrunk to fit.

**Settings** (in the menu):
- **Show Individual Windows:** list each app's windows under it so you can move them one at a time. On by
  default. When it's off, the menu lists apps only, and a checkmark marks apps whose windows are all on the
  display already.
- **Launch at Login.**

## Build and run

Needs macOS 13 or later and the Swift toolchain (the Xcode Command Line Tools are enough).

```sh
./scripts/build.sh            # builds build/Pullie.app
./scripts/build.sh --install  # also copies it to ~/Applications and launches it
```

On first launch, grant Pullie **Accessibility** access (System Settings › Privacy & Security ›
Accessibility). macOS needs this before one app can move another app's windows.

The build is signed ad hoc, so each rebuild looks like a new app to macOS and you have to grant access again.
`--install` clears the old entry for you. To keep the grant across rebuilds, sign with a stable identity:
`SIGN_IDENTITY="Apple Development: …" ./scripts/build.sh`.

The app icon is drawn in code by `scripts/make-icon.swift`. Run `swift scripts/make-icon.swift` to
regenerate `Resources/AppIcon.icns` after changing it.

## Notes

- **Icon on every display:** macOS shows a menu bar on each display only when **Displays have separate
  Spaces** is on (System Settings › Desktop & Dock). This is the default.
- **Which windows appear:** windows on each display's current Space, including minimized ones (these are
  restored when moved). Windows on other Spaces aren't listed, because macOS doesn't expose them to the
  Accessibility API.
- **Full-screen windows** are listed but can't be moved.

## License

MIT. See [LICENSE](LICENSE).
