#!/bin/sh
set -eu
destination=${1:-.tools}
version=dev-2026-10
ols=ec8606b97788d415d8b5ffa83782c7be52c6b14a
if [ -x "$destination/odin/odin" ] && [ -x "$destination/odinfmt" ] && [ "$(cat "$destination/version" 2>/dev/null)" = "$version/$ols" ]; then
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
curl --fail --location --retry 3 "https://github.com/odin-lang/Odin/releases/download/$version/odin-linux-amd64-$version.tar.gz" -o "$work/odin.tar.gz"
printf '%s  %s\n' c3c8b095621fd0c75f7f73e3a0829f1b4d45324225f20ba11ed8dc4da310a8ab "$work/odin.tar.gz" | sha256sum --check
mkdir "$work/odin" "$work/ols"
tar -xzf "$work/odin.tar.gz" --strip-components=1 -C "$work/odin"
curl --fail --location --retry 3 "https://codeload.github.com/DanielGavin/ols/tar.gz/$ols" -o "$work/ols.tar.gz"
printf '%s  %s\n' 9177999d9a443945b1d52fbda27fb01959bf75249c7adaf346951a38407c8379 "$work/ols.tar.gz" | sha256sum --check
tar -xzf "$work/ols.tar.gz" --strip-components=1 -C "$work/ols"
"$work/odin/odin" build "$work/ols/tools/odinfmt/main.odin" -file "-collection:src=$work/ols/src" "-out:$work/odinfmt" -o:speed
rm -rf "$destination/odin"
mv "$work/odin" "$destination/odin"
mv "$work/odinfmt" "$destination/odinfmt"
printf '%s\n' "$version/$ols" > "$destination/version"
