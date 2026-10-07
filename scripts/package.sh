#!/bin/sh
set -eu
sh scripts/validate-version.sh "$@"
version=$1
. /etc/os-release
if [ "$ID" != debian ] || [ "$VERSION_ID" != 13 ] || [ "$(uname -m)" != x86_64 ]; then
    echo 'Package inside the Debian 13 x86-64 release image.' >&2
    exit 1
fi
epoch=${SOURCE_DATE_EPOCH:-$(git show -s --format=%ct HEAD)}
commit=${RELEASE_COMMIT:-$(git rev-parse HEAD)}
printf '%s\n' "$epoch" | grep -Eq '^[0-9]+$'
printf '%s\n' "$commit" | grep -Eq '^[0-9a-f]{40}$'
name="my-bar-$version-linux-x86_64-debian13"
stage="build/package/$name"
output="build/release/$version"
rm -rf -- "$stage"
mkdir -p "$stage" "$output"
install -m 755 build/my-bar "$stage/my-bar"
strip --strip-unneeded "$stage/my-bar"
install -m 644 README.md LICENSE "$stage/"
printf 'version=%s\ncommit=%s\ntarget=debian13-x86_64\n' "$version" "$commit" > "$stage/BUILDINFO.txt"
tar --sort=name --mtime="@$epoch" --owner=0 --group=0 --numeric-owner \
    -C build/package -cf "build/package/$name.tar" "$name"
gzip -n -c "build/package/$name.tar" > "$output/$name.tar.gz"
rm -- "build/package/$name.tar"
(cd "$output" && sha256sum "$name.tar.gz" > SHA256SUMS)
printf 'Created %s/%s.tar.gz\n' "$output" "$name"
