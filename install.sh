#!/bin/bash
set -euo pipefail

source_dir="$(cd "$(/usr/bin/dirname "$0")" && pwd)"
source_app="${1:-$source_dir/dist/arm64/每秒拍照.app}"
target_dir="${2:-$HOME/Applications}"
target_app="$target_dir/每秒拍照.app"

[[ -d "$source_app/Contents/MacOS" ]] || {
  printf '找不到构建好的 App：%s\n请先运行 ./build.sh。\n' "$source_app" >&2
  exit 1
}
[[ ! -e "$target_app" ]] || {
  printf '目标已存在：%s\n请先在 Finder 中移走旧版 App，再重新安装。\n' "$target_app" >&2
  exit 1
}
/bin/mkdir -p "$target_dir"
stage=$(/usr/bin/mktemp -d "$target_dir/.interval-camera-install.XXXXXX")
trap '/bin/rm -rf "$stage"' EXIT
/usr/bin/ditto --norsrc --noextattr --noacl --noqtn "$source_app" "$stage/每秒拍照.app"
/usr/bin/codesign --verify --deep --strict "$stage/每秒拍照.app"
/bin/mv "$stage/每秒拍照.app" "$target_app"
printf '已安装：%s\n' "$target_app"
