#!/bin/sh
set -eu
mode=$1
compiler=$2
dub=$3
formatter=$4
scanner=$5
missing=0
require() {
    for tool do
        if ! command -v "$tool" >/dev/null 2>&1; then
            printf 'Missing executable: %s\n' "$tool" >&2
            missing=1
        fi
    done
}
case "$mode" in
    build|format|lint|test|package|release|all) ;;
    *) printf 'Unknown dependency group: %s\n' "$mode" >&2; exit 2 ;;
esac
case "$mode" in
    build|lint|test|package|all)
        require "$compiler" "$dub" cc pkg-config
        if command -v pkg-config >/dev/null 2>&1; then
            for library in x11 libsystemd 'json-c >= 0.19'; do
                if ! pkg-config --exists "$library"; then
                    printf 'Missing or incompatible development library: %s\n' "$library" >&2
                    missing=1
                fi
            done
        fi
        ;;
esac
case "$mode" in format|lint|all) require "$formatter" ;; esac
case "$mode" in lint|all) require "$scanner" ;; esac
case "$mode" in test|release|all) require jq dbus-daemon dbus-run-session timeout ;; esac
case "$mode" in
    package|release) require git strip tar gzip sha256sum makepkg namcap pacman fakeroot ;;
esac
case "$mode" in release) require shellcheck ;; esac
if [ "$missing" -ne 0 ]; then
    printf 'Install these dependencies yourself, then retry. Nothing was downloaded or installed.\n' >&2
    exit 1
fi
