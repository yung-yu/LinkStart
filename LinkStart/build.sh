#!/bin/bash

# Build parameters
APP_NAME="LinkStart"
APP_DIR="$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"

echo "🔨 Building $APP_NAME..."

# Create Bundle structure
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy App Icon
if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
    echo "🎨 Icon bundled."
fi

# Copy Localization files
if [ -d "Resources" ]; then
    cp -r Resources/*.lproj "$RESOURCES_DIR/" 2>/dev/null
    echo "🌍 Localization bundled."
fi

# Create Info.plist dynamically
cat << 'PLIST' > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>LinkStart</string>
    <key>CFBundleIdentifier</key>
    <string>com.example.LinkStart</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh-Hant</string>
    <key>CFBundleName</key>
    <string>LinkStart</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
PLIST

# Compile Swift code with optimization (-O) for release
swiftc -O Sources/*.swift -parse-as-library -o "$MACOS_DIR/$APP_NAME"

if [ $? -eq 0 ]; then
    echo "✅ Build successful! The App bundle is located at: $PWD/$APP_DIR"
    echo ""
    echo "📦 Creating DMG installer..."

    DMG_NAME="LinkStart.dmg"
    DMG_STAGING="dmg_staging"

    # Clean up previous staging/DMG
    rm -rf "$DMG_STAGING" "$DMG_NAME"
    mkdir -p "$DMG_STAGING"

    # Copy app into staging area
    cp -r "$APP_DIR" "$DMG_STAGING/"

    # Add a symlink to /Applications for drag-and-drop install
    ln -s /Applications "$DMG_STAGING/Applications"

    # Create compressed DMG using hdiutil
    hdiutil create \
        -volname "MacScrcpy" \
        -srcfolder "$DMG_STAGING" \
        -ov \
        -format UDZO \
        "$DMG_NAME"

    rm -rf "$DMG_STAGING"

    if [ $? -eq 0 ]; then
        echo "✅ DMG created: $PWD/$DMG_NAME"
    else
        echo "❌ DMG creation failed!"
        exit 1
    fi
else
    echo "❌ Build failed!"
    exit 1
fi
