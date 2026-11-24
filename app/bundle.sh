#!/usr/bin/env bash
# Assembla app/.build/devbar.app dal binario release. Il motore (bin/devbar, lib/) NON è nel
# bundle: resta nel repo, `~/.local/bin/devbar` lo raggiunge via symlink.
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
configuration="${1:-release}"
app="${package_dir}/.build/devbar.app"
identifier="${BUNDLE_IDENTIFIER:-it.savez.devbar}"
version="${BUNDLE_VERSION:-0.0.$(git -C "${package_dir}" rev-list --count HEAD 2>/dev/null || printf 0)}"
revision="${BUNDLE_REVISION:-$(git -C "${package_dir}" rev-parse HEAD 2>/dev/null || printf unknown)}"

rm -rf "${app}"
mkdir -p "${app}/Contents/MacOS" "${app}/Contents/Resources"
cp "${package_dir}/.build/${configuration}/Devbar" "${app}/Contents/MacOS/Devbar"
cp "${package_dir}/Info.plist" "${app}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${identifier}" "${app}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${version}" "${app}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${version}" "${app}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :DevbarRevision string ${revision}" "${app}/Contents/Info.plist"
codesign --force --sign - --identifier "${identifier}" "${app}"
codesign --verify --strict "${app}"
printf '%s\n' "${app}"
