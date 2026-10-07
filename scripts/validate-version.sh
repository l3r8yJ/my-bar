#!/bin/sh
set -eu
if [ "$#" -ne 1 ] || [ "$(printf '%s' "$1" | tr -cd 'v0-9.')" != "$1" ] || ! printf '%s\n' "$1" | grep -Eq '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'; then
    echo 'Expected a stable version tag: vMAJOR.MINOR.PATCH (for example v0.1.0)' >&2
    exit 1
fi
