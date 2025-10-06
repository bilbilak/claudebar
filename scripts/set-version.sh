#!/usr/bin/env bash
#
# Stamp a version into every platform-specific metadata file in the
# repository. The script is idempotent and is meant to run as the first
# step of each platform's release CI job, after `actions/checkout`, so the
# resulting artifacts carry the actual tagged version instead of whatever
# placeholder the source files happen to hold.
#
# Usage:
#     scripts/set-version.sh <version>          # e.g. 1.2.6
#
# The script writes a 3-segment SemVer string to every file that takes one,
# and a 4-segment "1.2.6.0" form to the Windows resource files that require
# it (the `.csproj` File/Assembly versions and `app.manifest` assemblyIdentity).
#
set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <version>" >&2
    echo "Example: $0 1.2.6" >&2
    exit 1
fi

VERSION="$1"
VERSION4="${VERSION}.0"

# Resolve the repository root regardless of how this script was invoked.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Portable in-place sed: GNU sed accepts `-i` with no argument; BSD/macOS sed
# requires an empty extension. Both honor `-i ''` if we pass it explicitly.
sed_in_place() {
    if sed --version >/dev/null 2>&1; then
        sed -i "$@"
    else
        sed -i '' "$@"
    fi
}

sed_in_place \
    -e '/<key>CFBundleShortVersionString<\/key>/{n;s|<string>[^<]*</string>|<string>'"$VERSION"'</string>|;}' \
    -e '/<key>CFBundleVersion<\/key>/{n;s|<string>[^<]*</string>|<string>'"$VERSION"'</string>|;}' \
    "$ROOT/apps/macos/Resources/Info.plist"

sed_in_place \
    -e 's|<Version>[^<]*</Version>|<Version>'"$VERSION"'</Version>|' \
    -e 's|<FileVersion>[^<]*</FileVersion>|<FileVersion>'"$VERSION4"'</FileVersion>|' \
    -e 's|<AssemblyVersion>[^<]*</AssemblyVersion>|<AssemblyVersion>'"$VERSION4"'</AssemblyVersion>|' \
    "$ROOT/apps/windows/ClaudeBar.csproj"

#    app.manifest: <assemblyIdentity version="x.y.z.w" .../> — 4-segment.
#    Anchor on the assemblyIdentity line so we don't rewrite `<?xml version=`.
sed_in_place \
    -e '/<assemblyIdentity/ s|version="[^"]*"|version="'"$VERSION4"'"|' \
    "$ROOT/apps/windows/app.manifest"

sed_in_place \
    -e 's|"version": "[^"]*"|"version": "'"$VERSION"'"|' \
    "$ROOT/apps/linux/gnome/package.json"

sed_in_place \
    -e 's|"Version": "[^"]*"|"Version": "'"$VERSION"'"|' \
    "$ROOT/apps/linux/kde/metadata.json"

sed_in_place \
    -e 's|"version": "[^"]*"|"version": "'"$VERSION"'"|' \
    "$ROOT/apps/linux/cinnamon/metadata.json"

sed_in_place \
    -e 's|^version = "[^"]*"$|version = "'"$VERSION"'"|' \
    "$ROOT/apps/linux/common/claudebar-helper/Cargo.toml"

# Cargo.lock holds a version per package entry. We update only our own
# package's version line so `cargo build --locked` keeps working in CI.
sed_in_place \
    -e '/^name = "claudebar-helper"$/{n;s|^version = "[^"]*"$|version = "'"$VERSION"'"|;}' \
    "$ROOT/apps/linux/common/claudebar-helper/Cargo.lock"

sed_in_place \
    -e '1,15s|"version": "[^"]*"|"version": "'"$VERSION"'"|' \
    "$ROOT/apps/linux/gnome/package-lock.json"

for f in \
    "$ROOT/apps/linux/xfce/meson.build" \
    "$ROOT/apps/linux/budgie/meson.build"; do
    sed_in_place \
        -e "s|version: '[0-9][^']*',|version: '$VERSION',|" \
        "$f"
done

sed_in_place \
    -e "s|project(claudebar-lxqt CXX VERSION [^)]*)|project(claudebar-lxqt CXX VERSION $VERSION)|" \
    "$ROOT/apps/linux/lxqt/CMakeLists.txt"

for pkg in \
    claudebar-helper \
    claudebar-gnome \
    claudebar-kde \
    claudebar-cinnamon \
    claudebar-xfce \
    claudebar-mate \
    claudebar-budgie \
    claudebar-lxqt; do
    sed_in_place \
        -e "s|^pkgver=[^[:space:]]*|pkgver=$VERSION|" \
        "$ROOT/packaging/arch/$pkg/PKGBUILD"
done

echo "Stamped version $VERSION (4-segment $VERSION4 where required) into:"
echo "  apps/macos/Resources/Info.plist"
echo "  apps/windows/ClaudeBar.csproj"
echo "  apps/windows/app.manifest"
echo "  apps/linux/gnome/package.json"
echo "  apps/linux/gnome/package-lock.json"
echo "  apps/linux/kde/metadata.json"
echo "  apps/linux/cinnamon/metadata.json"
echo "  apps/linux/xfce/meson.build"
echo "  apps/linux/budgie/meson.build"
echo "  apps/linux/lxqt/CMakeLists.txt"
echo "  apps/linux/common/claudebar-helper/Cargo.{toml,lock}"
echo "  packaging/arch/claudebar-*/PKGBUILD (8 files)"
