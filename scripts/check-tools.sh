#!/bin/sh
set -eu
tools=$1
shift
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
printf 'module probe;fn void main(){}\n' > "$work/probe.c3"
if "$tools/c3fmt" --check "$work/probe.c3" > "$work/output" 2>&1; then
    echo 'FAIL: formatter check accepted unformatted input.' >&2
    exit 1
fi
"$tools/c3fmt" -i "$work/probe.c3"
"$tools/c3fmt" --check "$work/probe.c3"
cat > "$work/probe.c3" <<'C3'
module probe;
excuse { BAD }
fn int? fail() { return BAD~; }
fn void main() { fail(); }
C3
if "$tools/c3/c3c" compile-only "$work/probe.c3" --no-obj "$@" > "$work/output" 2>&1; then
    echo 'FAIL: compiler accepted discarded optional results.' >&2
    exit 1
fi
grep -q 'optional and must be handled' "$work/output"
cat > "$work/probe.c3" <<'C3'
module probe;
fn void old() @deprecated("obsolete") {}
fn void main() { old(); }
C3
if "$tools/c3/c3c" compile-only "$work/probe.c3" --no-obj "$@" > "$work/output" 2>&1; then
    echo 'FAIL: compiler accepted a deprecation warning.' >&2
    exit 1
fi
grep -q 'error:.*deprecated' "$work/output"
printf 'module probe; fn void main() { goto end; end: return; }\n' > "$work/probe.c3"
if "$tools/c3/c3c" compile-only "$work/probe.c3" --no-obj "$@" > "$work/output" 2>&1; then
    echo 'FAIL: compiler accepted goto.' >&2
    exit 1
fi
cat > "$work/probe.c3" <<'C3'
module probe;
import std::core::mem;
fn void leaks() @test { void* pointer = mem::malloc(100); assert(pointer != null); }
C3
if "$tools/c3/c3c" compile-test "$work/probe.c3" -o "$work/probe" "$@" > "$work/output" 2>&1; then
    echo 'FAIL: test runner accepted a memory leak.' >&2
    exit 1
fi
grep -q 'LEAKS DETECTED' "$work/output"
printf 'PASS: formatting, optional results, warnings as errors, goto rejection and leak detection\n'
