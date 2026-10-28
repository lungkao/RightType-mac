#!/bin/bash
# Builds a universal (Apple Silicon + Intel) RightType.app and zips it with the
# licences and a Thai install guide, ready to send to friends.
set -euo pipefail
cd "$(dirname "$0")"
VER=0.1.0
MIN=13.0
OUT=build/dist/RightType.app/Contents
rm -rf build/dist; mkdir -p $OUT/MacOS $OUT/Resources build/icons
for T in aarch64 x86_64; do
  (cd ffi && cargo build --release --target $T-apple-darwin)
  swiftc -O -target $T-apple-macos$MIN -import-objc-header App/rt.h App/main.swift \
    ffi/target/$T-apple-darwin/release/librighttype_ffi.a \
    -framework Cocoa -framework Carbon -o build/RightType-$T
done
lipo -create build/RightType-aarch64 build/RightType-x86_64 -output $OUT/MacOS/RightType
swift tools/make_icons.swift build/icons
iconutil -c icns build/icons/AppIcon.iconset -o $OUT/Resources/AppIcon.icns
cp build/icons/menuTemplate*.png $OUT/Resources/
cat > $OUT/Info.plist <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>RightType</string>
<key>CFBundleDisplayName</key><string>RightType</string>
<key>CFBundleIdentifier</key><string>th.righttype.mac</string>
<key>CFBundleExecutable</key><string>RightType</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VER</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>$MIN</string>
</dict></plist>
PL
codesign --force --sign - -r='designated => identifier "th.righttype.mac"' build/dist/RightType.app
S=build/dist/RightType-mac-$VER; mkdir -p $S
cp -R build/dist/RightType.app $S/
cp ../LICENSE-MIT ../LICENSE-APACHE ../NOTICE $S/
cp INSTALL-TH.txt $S/"อ่านก่อน.txt"
(cd build/dist && ditto -c -k --norsrc --noextattr --keepParent RightType-mac-$VER RightType-mac-$VER.zip)
echo "Built: $(pwd)/build/dist/RightType-mac-$VER.zip"
