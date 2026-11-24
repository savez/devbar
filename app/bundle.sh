#!/usr/bin/env bash
# Assembla app/.build/devbar.app dal binario release. Il motore (bin/, lib/, statusline/) è
# copiato in Contents/Resources/engine: l'app funziona senza il repo.
# Variabili: BUNDLE_VERSION, BUNDLE_IDENTIFIER, BUNDLE_REVISION.
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
configuration="${1:-release}"
app="${package_dir}/.build/devbar.app"
identifier="${BUNDLE_IDENTIFIER:-it.savez.devbar}"
build_number="$(git -C "${package_dir}" rev-list --count HEAD 2>/dev/null || printf 0)"
version="${BUNDLE_VERSION:-0.0.${build_number}}"
revision="${BUNDLE_REVISION:-$(git -C "${package_dir}" rev-parse HEAD 2>/dev/null || printf unknown)}"

rm -rf "${app}"
mkdir -p "${app}/Contents/MacOS" "${app}/Contents/Resources"
cp "${package_dir}/.build/${configuration}/Devbar" "${app}/Contents/MacOS/Devbar"
cp "${package_dir}/Info.plist" "${app}/Contents/Info.plist"
cp "${package_dir}/Icon/AppIcon.icns" "${app}/Contents/Resources/AppIcon.icns"
repo_root="$(cd "${package_dir}/.." && pwd)"
engine="${app}/Contents/Resources/engine"
mkdir -p "${engine}"
cp -R "${repo_root}/bin" "${repo_root}/lib" "${repo_root}/statusline" "${engine}/"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${identifier}" "${app}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${version}" "${app}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${build_number}" "${app}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :DevbarRevision string ${revision}" "${app}/Contents/Info.plist"
codesign --force --sign - --identifier "${identifier}" "${app}"
codesign --verify --strict "${app}"
printf '%s\n' "${app}"
