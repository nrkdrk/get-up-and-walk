#!/bin/bash
set -e

APP="GetUpAndWalk.app"
BINARY="GetUpAndWalk"

if compgen -G "src/*.swift" > /dev/null; then
  SOURCES=(src/*.swift)
elif compgen -G "*.swift" > /dev/null; then
  SOURCES=(*.swift)
else
  echo "Error: no .swift sources found."
  exit 1
fi

rm -rf "$APP" build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# --- Icon --------------------------------------------------------------
ICON_SRC=""
for candidate in assets/icon.png icon.png; do
  [ -f "$candidate" ] && ICON_SRC="$candidate" && break
done

if [ -n "$ICON_SRC" ] && command -v iconutil > /dev/null; then
  echo "Building icon..."
  ICONSET="build/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$ICON_SRC" --out "$ICONSET/icon_${s}x${s}.png" > /dev/null
    sips -z $((s*2)) $((s*2)) "$ICON_SRC" --out "$ICONSET/icon_${s}x${s}@2x.png" > /dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  ICON_KEY="    <key>CFBundleIconFile</key>
    <string>AppIcon</string>"
else
  echo "No icon found, skipping."
  ICON_KEY=""
fi

# --- Bundle metadata ---------------------------------------------------
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>GetUpAndWalk</string>
    <key>CFBundleDisplayName</key>
    <string>Get Up and Walk</string>
    <key>CFBundleExecutable</key>
    <string>$BINARY</string>
    <key>CFBundleIdentifier</key>
    <string>com.github.nrkdrk.getupandwalk</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>3.1</string>
    <key>CFBundleVersion</key>
    <string>6</string>
$ICON_KEY
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# --- Compile -----------------------------------------------------------
# UNIVERSAL=1 builds both architectures and lipos them into one binary, which
# is what the release workflow ships so the download runs on Intel Macs too.
# A plain local build targets this machine only, and is quicker for it.
FRAMEWORKS=(-framework SwiftUI -framework AppKit -framework AVFoundation -framework UserNotifications)

if [ "${UNIVERSAL:-0}" = "1" ]; then
  echo "Compiling (universal)..."
  mkdir -p build
  for arch in arm64 x86_64; do
    echo "  $arch"
    swiftc -O "${SOURCES[@]}" -o "build/$BINARY-$arch" \
      -target "$arch-apple-macos13.0" "${FRAMEWORKS[@]}" -parse-as-library
  done
  lipo -create -output "$APP/Contents/MacOS/$BINARY" \
    "build/$BINARY-arm64" "build/$BINARY-x86_64"
else
  echo "Compiling..."
  swiftc -O "${SOURCES[@]}" -o "$APP/Contents/MacOS/$BINARY" \
    "${FRAMEWORKS[@]}" -parse-as-library
fi

echo "Signing (ad-hoc)..."
codesign --force --sign - "$APP" 2>/dev/null || echo "Signing skipped."

rm -rf build

echo ""
echo "Built: $(pwd)/$APP"
echo "Run:   open $APP"
