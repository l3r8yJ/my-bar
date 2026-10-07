#!/bin/sh
set -eu
sh scripts/validate-version.sh v0.1.0
for version in '' 0.1.0 v01.2.3 v1.2 v1.2.3-rc1 'v1.2.3/../escape' 'v1.2.3;exit 0'; do
    if sh scripts/validate-version.sh "$version" >/dev/null 2>&1; then
        echo 'FAIL: invalid release version accepted' >&2
        exit 1
    fi
done
version=${RELEASE_VERSION:-v0.0.0}
sh scripts/validate-version.sh "$version"
output="build/release/$version"
(cd "$output" && sha256sum --check SHA256SUMS)
name="my-bar-$version-linux-x86_64-debian13"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
tar -xzf "$output/$name.tar.gz" -C "$work"
for entry in my-bar README.md LICENSE BUILDINFO.txt; do
    test -s "$work/$name/$entry"
done
if readelf -SW "$work/$name/my-bar" | grep -q '\.symtab'; then
    echo 'FAIL: packaged binary is not stripped' >&2
    exit 1
fi
if readelf -d "$work/$name/my-bar" | grep -Eq 'libasan|libubsan'; then
    echo 'FAIL: sanitizer runtime in release binary' >&2
    exit 1
fi
MY_BAR_BIN="$work/$name/my-bar" sh tests/check.sh
before=$(sha256sum "$output/$name.tar.gz")
sh scripts/package.sh "$version"
test "$before" = "$(sha256sum "$output/$name.tar.gz")"
echo 'PASS: version validation, archive, stripped executable, and repeatable packaging'
