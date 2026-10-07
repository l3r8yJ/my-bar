#!/bin/sh
set -eu
formatter=$1
shift
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
find "$@" -type f -name '*.d' -exec sh -ec '
    formatter=$1
    work=$2
    shift 2
    for source do
        "$formatter" "$source" > "$work/formatted"
        if ! cmp -s "$source" "$work/formatted"; then
            diff -u "$source" "$work/formatted" || true
            exit 1
        fi
    done
' sh "$formatter" "$work" {} +
