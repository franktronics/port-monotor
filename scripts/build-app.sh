#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
configuration=${1:-release}
app_dir="$project_dir/dist/Port Monitor.app"
contents_dir="$app_dir/Contents"
module_cache="$project_dir/.build/module-cache"

mkdir -p "$module_cache"
env CLANG_MODULE_CACHE_PATH="$module_cache" \
    SWIFTPM_MODULECACHE_OVERRIDE="$module_cache" \
    swift build --disable-sandbox --package-path "$project_dir" -c "$configuration"

mkdir -p "$contents_dir/MacOS"
mkdir -p "$contents_dir/Resources"
cp "$project_dir/.build/$configuration/PortMonitor" "$contents_dir/MacOS/PortMonitor"
cp "$project_dir/Resources/Info.plist" "$contents_dir/Info.plist"
codesign --force --deep --sign - "$app_dir"

echo "Application created: $app_dir"
