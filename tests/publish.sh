#!/bin/sh
set -eu
script="$(pwd)/scripts/publish.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir "$work/bin" "$work/dist"
cat > "$work/bin/gh" <<'GH'
#!/bin/sh
set -eu
printf '%s\n' "$1 $2" >> "$GH_TEST_LOG"
case "$1 $2" in
    'release view')
        case "$GH_SCENARIO" in
            new) exit 1 ;;
            published) echo false ;;
            *) echo true ;;
        esac ;;
    'release create')
        case " $* " in *' --draft '*) ;; *) exit 1 ;; esac ;;
    'release upload') test "$GH_SCENARIO" != upload_failure ;;
    'release edit') test "$GH_SCENARIO" != upload_failure ;;
    *) exit 1 ;;
esac
GH
chmod 755 "$work/bin/gh"
export PATH="$work/bin:$PATH" GH_TEST_LOG="$work/commands"
printf 'package fixture\n' > "$work/dist/package.tar.gz"
printf 'arch package fixture\n' > "$work/dist/package.pkg.tar.zst"
printf 'recipe fixture\n' > "$work/dist/PKGBUILD"
printf 'metadata fixture\n' > "$work/dist/.SRCINFO"
cd "$work/dist"
sha256sum package.tar.gz package.pkg.tar.zst PKGBUILD .SRCINFO > SHA256SUMS
for GH_SCENARIO in new draft published upload_failure; do
    export GH_SCENARIO
    : > "$GH_TEST_LOG"
    if sh "$script" v0.1.0 >/dev/null 2>&1; then
        test "$GH_SCENARIO" != upload_failure
    else
        test "$GH_SCENARIO" = upload_failure
    fi
    case "$GH_SCENARIO" in
        new) expected='release view
release create
release edit' ;;
        draft) expected='release view
release upload
release edit' ;;
        published) expected='release view' ;;
        upload_failure) expected='release view
release upload' ;;
    esac
    test "$(cat "$GH_TEST_LOG")" = "$expected"
done
printf 'tampered\n' >> package.tar.gz
: > "$GH_TEST_LOG"
if sh "$script" v0.1.0 >/dev/null 2>&1; then
    echo 'FAIL: publishing accepted a checksum mismatch' >&2
    exit 1
fi
test ! -s "$GH_TEST_LOG"
echo 'PASS: new release, draft retry, immutable publication, failed upload, and checksum rejection'
