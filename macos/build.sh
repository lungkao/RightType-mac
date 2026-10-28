#!/bin/bash
# Builds RightType.app (menu-bar app) from the Rust core + Swift shell.
set -euo pipefail
cd "$(dirname "$0")"
(cd ffi && cargo build --release)
OUT=build/RightType.app/Contents
mkdir -p $OUT/MacOS $OUT/Resources
swift tools/make_icons.swift build/icons
iconutil -c icns build/icons/AppIcon.iconset -o $OUT/Resources/AppIcon.icns
cp build/icons/menuTemplate*.png $OUT/Resources/
swiftc -O -import-objc-header App/rt.h App/main.swift ffi/target/release/librighttype_ffi.a \
  -framework Cocoa -framework Carbon -o $OUT/MacOS/RightType
cat > $OUT/Info.plist <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>RightType</string>
<key>CFBundleDisplayName</key><string>RightType</string>
<key>CFBundleIdentifier</key><string>th.righttype.mac</string>
<key>CFBundleExecutable</key><string>RightType</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>12.0</string>
</dict></plist>
PL
# Ad-hoc signing with a fixed designated requirement, so macOS keeps the
# Accessibility permission across rebuilds (a plain ad-hoc hash changes every build).
codesign --force --sign - -r='designated => identifier "th.righttype.mac"' build/RightType.app
echo "Built: $(pwd)/build/RightType.app"
