#!/bin/sh
set -eu
destination=${1:-.tools}
version=0.8.4
formatter=0.3.3
if [ -x "$destination/c3/c3c" ] && [ -x "$destination/c3fmt" ] && [ "$(cat "$destination/version" 2>/dev/null)" = "$version/$formatter" ]; then
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
curl --fail --location --retry 3 "https://github.com/c3lang/c3c/releases/download/v$version/c3-linux.tar.gz" -o "$work/c3.tar.gz"
printf '%s  %s\n' 224b9a706761cc1e54e2bf26bcd777edd0971f5fbc773016957071b11ff084c9 "$work/c3.tar.gz" | sha256sum --check
mkdir "$work/c3"
tar -xzf "$work/c3.tar.gz" --strip-components=1 -C "$work/c3"
"$work/c3/c3c" --version
curl --fail --location --retry 3 "https://github.com/lmichaudel/c3fmt/releases/download/v$formatter/c3fmt-linux" -o "$work/c3fmt"
printf '%s  %s\n' 4dbb69372d4bd9695732ac5cd01f0f4de3adb7df1beb8c50cc97465a935a2820 "$work/c3fmt" | sha256sum --check
chmod +x "$work/c3fmt"
"$work/c3fmt" --version
rm -rf "$destination/c3"
mv "$work/c3" "$destination/c3"
mv "$work/c3fmt" "$destination/c3fmt"
printf '%s\n' "$version/$formatter" > "$destination/version"
