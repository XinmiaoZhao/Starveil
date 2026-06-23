#!/bin/zsh
set -euo pipefail

APP_NAME="Starveil"
PRODUCT_NAME="MySequatorApp"
BUNDLE_ID="research.zhaoxinmiao.starveil"
MARKETING_VERSION="0.7.0"

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
BACKUP_ROOT="${BACKUP_ROOT:-$PROJECT_DIR/AppBackups}"
TARGET_APP="$INSTALL_DIR/$APP_NAME.app"
ICON_PATH="$PROJECT_DIR/Resources/AppIcon.icns"
EXECUTABLE_PATH="$PROJECT_DIR/.build/release/$PRODUCT_NAME"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ ! -f "$ICON_PATH" ]]; then
  print -u2 "Missing icon: $ICON_PATH"
  exit 1
fi

cd "$PROJECT_DIR"
swift build -c release --product "$PRODUCT_NAME"

BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || date +%Y%m%d%H%M%S)"
GIT_REVISION="$(git rev-parse --short HEAD 2>/dev/null || print local)"
STAGE_DIR="$(mktemp -d "$PROJECT_DIR/.build/starveil-stage.XXXXXX")"
STAGED_APP="$STAGE_DIR/$APP_NAME.app"
trap 'rm -rf "$STAGE_DIR"' EXIT

mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
/usr/bin/install -m 755 "$EXECUTABLE_PATH" "$STAGED_APP/Contents/MacOS/$APP_NAME"
/usr/bin/ditto "$ICON_PATH" "$STAGED_APP/Contents/Resources/AppIcon.icns"
print "APPL????" > "$STAGED_APP/Contents/PkgInfo"

cat > "$STAGED_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$MARKETING_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.photography</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Independent astrophotography stacker build $GIT_REVISION.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$STAGED_APP" >/dev/null 2>&1 || \
    print -u2 "Warning: ad-hoc codesign failed; installing unsigned app bundle."
fi

mkdir -p "$INSTALL_DIR" "$BACKUP_ROOT"

if [[ -d "$TARGET_APP" ]]; then
  timestamp="$(date +%Y%m%d-%H%M%S)"
  backup_app="$BACKUP_ROOT/PreviousLaunchpadBuild-$timestamp.app"
  counter=1
  while [[ -e "$backup_app" ]]; do
    backup_app="$BACKUP_ROOT/PreviousLaunchpadBuild-$timestamp-$counter.app"
    counter=$((counter + 1))
  done
  /bin/mv "$TARGET_APP" "$backup_app"
  print "Backed up previous launchpad build to $backup_app"
fi

/usr/bin/ditto "$STAGED_APP" "$TARGET_APP"
/usr/bin/xattr -cr "$TARGET_APP" 2>/dev/null || true
/usr/bin/touch "$TARGET_APP"

if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$TARGET_APP" >/dev/null 2>&1 || true
fi

print "Installed $APP_NAME to $TARGET_APP"
print "Launchpad should list it as $APP_NAME. If Launchpad is already open, close and reopen it to refresh the grid."
