#!/bin/bash
# Builds RightType and installs it to /Applications, then launches it
# (it registers itself to start at login on first run).
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
pkill RightType 2>/dev/null || true
rm -rf /Applications/RightType.app
cp -R build/RightType.app /Applications/
open /Applications/RightType.app
echo "Installed: /Applications/RightType.app"
