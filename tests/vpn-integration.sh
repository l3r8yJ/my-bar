#!/bin/sh
set -eu
if [ "${1:-}" != --session ]; then
    exec timeout 45s dbus-run-session -- sh "$0" --session
fi
server=${VPN_SERVICE_BIN:-./build/vpn-service}
client=${VPN_TEST_BIN:-./build/test-vpn}
work=$(mktemp -d)
pid=
cleanup() {
    if [ -n "$pid" ]; then
        kill "$pid" 2>/dev/null || true
        wait "$pid" || true
    fi
    rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM
mkfifo "$work/ready"
export DBUS_SYSTEM_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS"
MY_BAR_VPN_EXPECT='VPN: unavailable' MY_BAR_VPN_COLOR='#888888' "$client"
for mode in 0 1 2 3 4; do
    "$server" "$mode" > "$work/ready" &
    pid=$!
    read -r ready < "$work/ready"
    test "$ready" = ready
    color='#888888'
    iterations=20
    case "$mode" in
        0) expected='VPN: office "quoted", wg, tun'; color='#00cc66' ;;
        1) expected='VPN: off' ;;
        2) expected='VPN: unavailable' ;;
        3) expected="VPN: $(printf '%8191s' '' | tr ' ' x)"; color='#00cc66' ;;
        4) expected='VPN: unavailable'; iterations=1 ;;
    esac
    MY_BAR_VPN_EXPECT="$expected" MY_BAR_VPN_COLOR="$color" MY_BAR_VPN_ITERATIONS="$iterations" "$client"
    kill "$pid"
    wait "$pid"
    pid=
    MY_BAR_VPN_EXPECT='VPN: unavailable' MY_BAR_VPN_COLOR='#888888' "$client"
done
echo 'PASS: private D-Bus VPN filtering, missing properties, long names, timeouts, and service restart'
