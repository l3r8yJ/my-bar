#!/bin/sh
set -eu
sh scripts/validate-version.sh "$@"
version=$1
. /etc/os-release
if [ "$ID" != arch ] || [ "$(uname -m)" != x86_64 ]; then
    echo 'Package inside the Arch Linux x86-64 release image.' >&2
    exit 1
fi
epoch=${SOURCE_DATE_EPOCH:-$(git show -s --format=%ct HEAD)}
commit=${RELEASE_COMMIT:-$(git rev-parse HEAD)}
printf '%s\n' "$epoch" | grep -Eq '^[0-9]+$'
printf '%s\n' "$commit" | grep -Eq '^[0-9a-f]{40}$'
name="my-bar-$version-linux-x86_64-arch"
stage="build/package/$name"
output="build/release/$version"
rm -rf -- "$stage" "$output"
mkdir -p "$stage" "$output"
install -m 755 build/my-bar "$stage/my-bar"
strip --strip-unneeded "$stage/my-bar"
install -m 644 README.md LICENSE "$stage/"
printf 'version=%s\ncommit=%s\ntarget=arch-x86_64\n' "$version" "$commit" > "$stage/BUILDINFO.txt"
tar --sort=name --mtime="@$epoch" --owner=0 --group=0 --numeric-owner \
    -C build/package -cf "build/package/$name.tar" "$name"
gzip -n -c "build/package/$name.tar" > "$output/$name.tar.gz"
rm -- "build/package/$name.tar"
recipe="build/package/aur-$version"
rm -rf -- "$recipe"
mkdir -p "$recipe"
checksum=$(sha256sum "$output/$name.tar.gz" | cut -d ' ' -f 1)
sed -e "s/@VERSION@/${version#v}/g" -e "s/@SHA256@/$checksum/g" \
    release/PKGBUILD.in > "$recipe/PKGBUILD"
cp "$output/$name.tar.gz" "$recipe/"
(cd "$recipe" && makepkg --force --nodeps && makepkg --printsrcinfo > .SRCINFO)
cp "$recipe/PKGBUILD" "$recipe/"*.pkg.tar.zst "$output/"
cp "$recipe/.SRCINFO" "$output/SRCINFO"
namcap -m "$recipe/PKGBUILD" "$output/"*.pkg.tar.zst > "$recipe/namcap.log"
sed '/^my-bar-bin W: dependency-not-needed i3status$/d' "$recipe/namcap.log" > "$recipe/namcap-checked.log"
cat "$recipe/namcap-checked.log"
if grep -Eq ' (E|W): ' "$recipe/namcap-checked.log"; then
    echo 'FAIL: package lint reported errors or warnings' >&2
    exit 1
fi
(cd "$output" && sha256sum ./*.tar.gz ./*.pkg.tar.zst PKGBUILD SRCINFO > SHA256SUMS)
printf 'Created %s/%s.tar.gz\n' "$output" "$name"
