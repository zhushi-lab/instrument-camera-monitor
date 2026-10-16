#!/bin/bash
set -euo pipefail

source_dir="$(cd "$(/usr/bin/dirname "$0")" && pwd)"
output_dir="${1:-$source_dir/dist/arm64}"
app="$output_dir/每秒拍照.app"
archive="$output_dir/每秒拍照-macos-arm64.zip"
[[ ! -e "$app" && ! -e "$archive" ]] || {
  printf '输出文件已存在，请选择空目录：%s\n' "$output_dir" >&2
  exit 1
}

sdk="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
work="$(/usr/bin/mktemp -d)"
trap '/bin/rm -rf "$work"' EXIT
stage="$work/每秒拍照.app"
resources="$stage/Contents/Resources"
/bin/mkdir -p "$stage/Contents/MacOS" "$resources/CaptureMenu.app/Contents/MacOS"

# Convert the selected high-resolution icon into every macOS icon size.
icon_source="$source_dir/assets/icon-concepts/03-frame-sequence.png"
iconset="$work/AppIcon.iconset"
/bin/mkdir "$iconset"
for size in 16 32 128 256 512; do
  double=$((size * 2))
  /usr/bin/sips -s format png -z "$size" "$size" "$icon_source" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  /usr/bin/sips -s format png -z "$double" "$double" "$icon_source" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$iconset" -o "$resources/AppIcon.icns"

build_swift() {
  local source="$1" destination="$2"
  /usr/bin/xcrun swiftc -O -sdk "$sdk" -target arm64-apple-macosx13.0 \
    -module-cache-path "$work/swift-arm64" \
    -Xcc "-fmodules-cache-path=$work/clang-arm64" \
    "$source_dir/$source" -o "$destination"
  /bin/chmod 755 "$destination"
  /usr/bin/codesign --force --sign - "$destination"
}

build_swift AppLauncher.swift "$stage/Contents/MacOS/IntervalCamera"
build_swift CaptureMenu.swift "$resources/CaptureMenu.app/Contents/MacOS/CaptureMenu"
build_swift RegionPicker.swift "$resources/RegionPicker"
build_swift InstrumentOCR.swift "$resources/InstrumentOCR"
build_swift MailSecret.swift "$resources/MailSecret"

for name in capture_with_imagesnap.sh configure_mail.sh capacity_estimate.py photo_storage.py monitor_instrument.py mail_delivery.py; do
  /bin/cp "$source_dir/$name" "$resources/$name"
done
/bin/chmod 755 "$resources/capture_with_imagesnap.sh" "$resources/configure_mail.sh"

/bin/cat > "$stage/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.yushaofen.imagesnap-timelapse</string>
<key>CFBundleName</key><string>每秒拍照</string>
<key>CFBundleDisplayName</key><string>每秒拍照</string>
<key>CFBundleExecutable</key><string>IntervalCamera</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundleVersion</key><string>195</string>
<key>CFBundleShortVersionString</key><string>1.9.5</string>
<key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSCameraUsageDescription</key><string>用于按设定间隔拍摄仪器照片。</string>
</dict></plist>
PLIST
/bin/cat > "$resources/CaptureMenu.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.yushaofen.imagesnap-timelapse.menu</string>
<key>CFBundleName</key><string>拍照菜单</string>
<key>CFBundleExecutable</key><string>CaptureMenu</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>195</string>
<key>CFBundleShortVersionString</key><string>1.9.5</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST

/usr/bin/codesign --force --sign - "$resources/CaptureMenu.app"
/usr/bin/codesign --force --sign - "$stage"
/usr/bin/codesign --verify --deep --strict "$stage"
/bin/mkdir -p "$output_dir"
/bin/mv "$stage" "$app"
release="$work/每秒拍照-macos-arm64"
/bin/mkdir -p "$release"
/usr/bin/ditto --norsrc --noextattr --noacl --noqtn "$app" "$release/每秒拍照.app"
/bin/cp "$source_dir/README.md" "$source_dir/LICENSE" "$release/"
/usr/bin/ditto -c -k --keepParent --norsrc --noextattr --noacl --noqtn "$release" "$archive"
( cd "$output_dir" && /usr/bin/shasum -a 256 "$(/usr/bin/basename "$archive")" > "$(/usr/bin/basename "$archive").sha256" )
printf 'App: %s\nZIP: %s\n' "$app" "$archive"
