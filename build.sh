#!/bin/zsh
set -euo pipefail
cd -- "${0:A:h}"
app=".build/音频自动切换.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
mkdir -p .build/daemon .build/control
cp Sources/AudioPriority.swift .build/daemon/main.swift
cp Sources/Control.swift .build/control/main.swift
swiftc -target arm64-apple-macosx13.0 -O Sources/AudioModel.swift .build/daemon/main.swift -o "$app/Contents/MacOS/audio-priority"
swiftc -target arm64-apple-macosx13.0 -O Sources/AudioModel.swift Sources/ServiceManager.swift .build/control/main.swift -o "$app/Contents/MacOS/control"
cp Assets/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>音频自动切换</string>
<key>CFBundleDisplayName</key><string>音频自动切换</string>
<key>CFBundleIdentifier</key><string>local.audio-priority.control</string>
<key>CFBundleExecutable</key><string>control</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundleShortVersionString</key><string>1.2.0</string>
<key>CFBundleVersion</key><string>5</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF
codesign --force --sign - "$app"
codesign --verify --strict "$app"
echo "Built: $app"
