#!/usr/bin/env bash
# Builds Pullie.app into ./build. Pass --install to also copy it to ~/Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Pullie.app"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/Pullie"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Pullie"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Use a real identity if one is given (keeps the Accessibility grant across rebuilds); otherwise sign ad hoc.
codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  DEST="$HOME/Applications/Pullie.app"
  pkill -x Pullie 2>/dev/null || true
  mkdir -p "$HOME/Applications"
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  if [[ "${SIGN_IDENTITY:--}" == "-" ]]; then
    # An ad hoc signature changes on every build, so the old Accessibility grant no longer
    # matches. Clear it so macOS prompts afresh rather than showing a stale, non-working entry.
    tccutil reset Accessibility dev.pullie.Pullie >/dev/null 2>&1 || true
  fi
  open "$DEST"
  echo "Installed and launched $DEST"
fi
