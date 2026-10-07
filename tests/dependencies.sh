#!/bin/sh
set -eu
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
if PATH="$work" /bin/sh scripts/check-deps.sh all ldc2 dub dfmt dscanner > "$work/output" 2>&1; then
    echo 'FAIL: missing dependencies were accepted' >&2
    exit 1
fi
for tool in ldc2 dub dfmt dscanner cc pkg-config jq dbus-daemon dbus-run-session timeout; do
    grep -qx "Missing executable: $tool" "$work/output"
done
test "$(find "$work" -mindepth 1 | wc -l)" -eq 1
sh scripts/check-deps.sh format absent-compiler absent-dub sh absent-scanner
printf 'PASS: missing dependencies reported together, no installation, independent formatter requirements\n'
