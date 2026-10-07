#!/bin/sh
set -eu
scanner=$1
shift
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
find "$@" -type f -name '*.d' -exec sh -ec '
    scanner=$1
    work=$2
    shift 2
    for source do
        "$scanner" --ast "$source" > "$work/ast.xml"
        if grep -q "<gotoStatement" "$work/ast.xml"; then
            printf "%s: goto statements are forbidden\n" "$source" >&2
            exit 1
        fi
    done
' sh "$scanner" "$work" {} +
