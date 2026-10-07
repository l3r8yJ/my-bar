#!/bin/sh
set -eu
compiler=$1
formatter=$2
scanner=$3
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
printf 'module probe;extern(C) int main(){return 0;}\n' > "$work/probe.d"
if sh scripts/check-format.sh "$formatter" "$work" > "$work/output" 2>&1; then
    echo 'FAIL: formatter accepted unformatted source.' >&2
    exit 1
fi
"$formatter" --inplace "$work/probe.d"
sh scripts/check-format.sh "$formatter" "$work"
printf 'module probe; int[] allocate() @nogc nothrow { return new int[1]; }\n' > "$work/probe.d"
if "$compiler" -w -de -c "$work/probe.d" -of="$work/probe.o" > "$work/output" 2>&1; then
    echo 'FAIL: compiler accepted GC allocation in @nogc function.' >&2
    exit 1
fi
grep -q 'GC allocation' "$work/output"
printf 'module probe; extern(C) void allocate() nothrow; void run() @nogc nothrow { allocate(); }\n' > "$work/probe.d"
if "$compiler" -betterC -w -de -c "$work/probe.d" -of="$work/probe.o" > "$work/output" 2>&1; then
    echo 'FAIL: BetterC compiler accepted call without @nogc.' >&2
    exit 1
fi
grep -q 'non-@nogc' "$work/output"
printf 'module probe; extern(C) void fail() @nogc; void run() @nogc nothrow { fail(); }\n' > "$work/probe.d"
if "$compiler" -betterC -w -de -c "$work/probe.d" -of="$work/probe.o" > "$work/output" 2>&1; then
    echo 'FAIL: BetterC compiler accepted call without nothrow.' >&2
    exit 1
fi
grep -q 'nothrow' "$work/output"
printf 'module probe; void fail() @nogc nothrow { throw new Exception("failure"); }\n' > "$work/probe.d"
if "$compiler" -betterC -w -de -c "$work/probe.d" -of="$work/probe.o" > "$work/output" 2>&1; then
    echo 'FAIL: BetterC compiler accepted throwing.' >&2
    exit 1
fi
grep -q 'throw' "$work/output"
printf 'module probe; import ldc.attributes : optStrategy; @optStrategy("invalid") extern(C) int main() { return 0; }\n' > "$work/probe.d"
if "$compiler" -betterC -w -de -c "$work/probe.d" -of="$work/probe.o" > "$work/output" 2>&1; then
    echo 'FAIL: compiler accepted a warning.' >&2
    exit 1
fi
grep -q 'Warning: ignoring unrecognized parameter' "$work/output"
printf 'module probe; deprecated void old() {} void run() { old(); }\n' > "$work/probe.d"
if "$compiler" -betterC -w -de -c "$work/probe.d" -of="$work/probe.o" > "$work/output" 2>&1; then
    echo 'FAIL: compiler accepted a deprecated call.' >&2
    exit 1
fi
grep -q 'deprecated' "$work/output"
printf 'module probe; void run() { goto finish; finish: return; }\n' > "$work/probe.d"
if sh scripts/check-policy.sh "$scanner" "$work" > "$work/output" 2>&1; then
    echo 'FAIL: syntax-tree policy accepted goto.' >&2
    exit 1
fi
printf 'module probe; enum text = "<gotoStatement goto"; // goto\n' > "$work/probe.d"
sh scripts/check-policy.sh "$scanner" "$work"
printf 'module probe; int produce() { return 1; } void run() { produce(); }\n' > "$work/probe.d"
if "$scanner" --styleCheck --config=dscanner.ini "$work/probe.d" > "$work/output" 2>&1; then
    echo 'FAIL: analyzer accepted a discarded result.' >&2
    exit 1
fi
grep -q 'return value is discarded' "$work/output"
cat > "$work/probe.d" <<'D'
module probe;
import core.stdc.stdlib : malloc;
extern(C) int main() @nogc nothrow { cast(void)malloc(64); return 0; }
D
"$compiler" -betterC -w -de -g -fsanitize=address "$work/probe.d" -of="$work/probe"
if ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 "$work/probe" > "$work/output" 2>&1; then
    echo 'FAIL: sanitizer accepted a memory leak.' >&2
    exit 1
fi
grep -q 'LeakSanitizer' "$work/output"
printf 'PASS: formatter, GC/throw rejection, fatal warnings, AST goto ban, unused results and leak detection\n'
