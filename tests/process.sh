#!/bin/sh
set -eu
if [ "${1:-}" != --bounded ]; then
    exec timeout 15 sh "$0" --bounded
fi
bar=${MY_BAR_BIN:-./build/my-bar}
work=$(mktemp -d)
bar_pid=
cleanup() {
    if [ -n "$bar_pid" ]; then
        kill -TERM "$bar_pid" 2>/dev/null || true
        wait "$bar_pid" 2>/dev/null || true
    fi
    rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM
export PATH="$work:$PATH" MY_BAR_TEST_WORK="$work"
mkfifo "$work/ready" "$work/gate" "$work/output"
cat > "$work/i3status" <<'SH'
#!/bin/sh
printf '%s\n' "$$" > "$MY_BAR_TEST_WORK/ready"
exec sleep 30
SH
chmod +x "$work/i3status"
for signal in TERM INT; do
    "$bar" > "$work/stream" 2> "$work/error" &
    bar_pid=$!
    read -r child_pid < "$work/ready"
    kill -"$signal" "$bar_pid"
    wait "$bar_pid"
    bar_pid=
    test ! -e "/proc/$child_pid"
done
cat > "$work/i3status" <<'SH'
#!/bin/sh
printf '%s\n' "$$" > "$MY_BAR_TEST_WORK/ready"
read -r release < "$MY_BAR_TEST_WORK/gate"
printf '%s\n' '{"version":1}' '[' '[{"full_text":"clock"}]'
SH
"$bar" --once > "$work/output" 2> "$work/error" &
bar_pid=$!
exec 4< "$work/output"
read -r child_pid < "$work/ready"
exec 4<&-
printf '%s\n' go > "$work/gate"
if wait "$bar_pid"; then
    echo 'FAIL: accepted broken stdout pipe' >&2
    exit 1
else
    result=$?
fi
bar_pid=
test "$result" -eq 1
test ! -e "/proc/$child_pid"
if "$bar" --wrong > /dev/null 2> "$work/error"; then
    echo 'FAIL: accepted unknown argument' >&2
    exit 1
else
    result=$?
fi
test "$result" -eq 2
cat > "$work/i3status" <<'SH'
#!/bin/sh
printf '%s\n' '{"version":1}' '['
printf '%s' '[{"full_text":"clock"}]'
SH
"$bar" --once > "$work/frame" 2> "$work/error"
jq -e '.[2].full_text == " clock "' "$work/frame" > /dev/null
echo 'PASS: idle SIGTERM/SIGINT, child reaping, broken pipe, exit 2, partial final line'
