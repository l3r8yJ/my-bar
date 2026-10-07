#!/bin/sh
set -eu
tools=$1
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
printf 'package probe\nmain::proc(){ }\n' > "$work/probe.odin"
if sh scripts/check-format.sh "$tools/odinfmt" "$work" > "$work/output" 2>&1; then
    echo 'FAIL: formatter check accepted unformatted input.' >&2
    exit 1
fi
"$tools/odinfmt" "$work/probe.odin" -w
sh scripts/check-format.sh "$tools/odinfmt" "$work"
cat > "$work/probe.odin" <<'ODIN'
package probe
@(require_results)
fallible :: proc() -> bool { return false }
main :: proc() { fallible() }
ODIN
if "$tools/odin/odin" check "$work" > "$work/output" 2>&1; then
    echo 'FAIL: compiler accepted discarded required results.' >&2
    exit 1
fi
grep -q 'requires that its results must be handled' "$work/output"
printf 'PASS: formatting and required-result checks\n'
