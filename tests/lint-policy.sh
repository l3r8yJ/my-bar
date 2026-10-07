#!/bin/sh
set -eu
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
cat > "$work/valid.c" <<'C'
const char *sample(void);
const char *sample(void) { /* goto is allowed in comments. */ return "goto"; }
C
cat > "$work/direct.c" <<'C'
int sample(void);
int sample(void) { goto done; done: return 0; }
C
cat > "$work/macro.c" <<'C'
#define JUMP goto
int sample(void);
int sample(void) { JUMP done; done: return 0; }
C
cat > "$work/indirect.c" <<'C'
int sample(void);
int sample(void) { void *label = &&done; goto *label; done: return 0; }
C
for compiler in cc clang; do
    "$compiler" -std=c17 -Werror -include lint/no-goto.h -fsyntax-only "$work/valid.c"
    for fixture in direct macro indirect; do
        if "$compiler" -std=c17 -Werror -include lint/no-goto.h -fsyntax-only "$work/$fixture.c" > "$work/log" 2>&1; then
            echo "FAIL: $compiler accepted $fixture jump" >&2
            exit 1
        fi
        grep -q 'poisoned' "$work/log"
    done
done
clang-tidy --config-file=.clang-tidy "$work/valid.c" -- -std=c17 -include "$PWD/lint/no-goto.h" > "$work/log" 2>&1
if clang-tidy --config-file=.clang-tidy "$work/direct.c" -- -std=c17 -include "$PWD/lint/no-goto.h" > "$work/log" 2>&1; then
    echo 'FAIL: clang-tidy accepted a jump' >&2
    exit 1
fi
grep -q 'poisoned' "$work/log"
echo 'PASS: compilers and lint reject direct, macro and computed jumps; comments and strings remain valid'
cat > "$work/result.c" <<'C'
#include "error/result.h"
MUST_USE StringResult sample(void);
StringResult sample(void) { return (StringResult){0}; }
int main(void) { sample(); return 0; }
C
for compiler in cc clang; do
    if "$compiler" -std=c17 -Werror -Isrc -c -o /dev/null "$work/result.c" > "$work/result.log" 2>&1; then
        echo "FAIL: $compiler accepts an ignored result" >&2
        exit 1
    fi
    if ! grep -q 'unused-result' "$work/result.log"; then
        cat "$work/result.log" >&2
        exit 1
    fi
done
echo 'PASS: ignored results are rejected'
