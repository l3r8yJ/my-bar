#!/bin/sh
set -eu
destination=${1:-.tools}
version=1.43.0
dfmt_revision=d8e43e23eca0aa32f064fe7efe8e74a9efa8018e
dscanner_revision=1201a68f662a300eacae4f908a87d4cd57f2032e
identity="$version/$dfmt_revision/$dscanner_revision"
if [ -x "$destination/ldc/bin/ldc2" ] && [ -x "$destination/dfmt" ] && [ -x "$destination/dscanner" ] && [ "$(cat "$destination/version" 2>/dev/null)" = "$identity" ]; then
    exit 0
fi
if [ "$(uname -s)/$(uname -m)" != Linux/x86_64 ]; then
    echo 'The pinned toolchain requires Linux x86-64.' >&2
    exit 1
fi
mkdir -p "$destination"
destination=$(cd "$destination" && pwd)
work=$(mktemp -d "$destination/setup.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
curl --fail --location --retry 3 "https://github.com/ldc-developers/ldc/releases/download/v$version/ldc2-$version-linux-x86_64.tar.xz" -o "$work/ldc.tar.xz"
printf '%s  %s\n' 35805db60f47fd1a162b2035da84d96beec37e6d1e7b1edf60498a90acfaedce "$work/ldc.tar.xz" | sha256sum --check
mkdir "$work/ldc"
tar -xJf "$work/ldc.tar.xz" --strip-components=1 -C "$work/ldc"
for tool in dfmt dscanner; do
    case "$tool" in
        dfmt) repository=dfmt; revision=$dfmt_revision ;;
        dscanner) repository=D-Scanner; revision=$dscanner_revision ;;
    esac
    git clone --quiet --depth 1 --branch v0.15.2 "https://github.com/dlang-community/$repository.git" "$work/$tool"
    test "$(git -C "$work/$tool" rev-parse HEAD)" = "$revision"
    git -C "$work/$tool" submodule update --init --recursive --depth 1
    PATH="$work/ldc/bin:$PATH" make -C "$work/$tool" DC=ldmd2 > "$work/$tool.log" 2>&1 || { cat "$work/$tool.log"; exit 1; }
done
rm -rf "$destination/ldc"
mv "$work/ldc" "$destination/ldc"
install -m 755 "$work/dfmt/bin/dfmt" "$destination/dfmt"
install -m 755 "$work/dscanner/bin/dscanner" "$destination/dscanner"
printf '%s\n' "$identity" > "$destination/version"
