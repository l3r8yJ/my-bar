#!/bin/sh
set -eu
bar=${MY_BAR_BIN:-./build/my-bar}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
cat > "$work/i3status" <<'SH'
#!/bin/sh
printf '%s\n' '{"version":1}' '['
i=0
while [ "$i" -lt "${MY_BAR_FRAMES:-1}" ]; do
    printf '%s\n' "$MY_BAR_FRAME"
    i=$((i + 1))
done
SH
chmod +x "$work/i3status"
export PATH="$work:$PATH"
export MY_BAR_FRAME='[{"full_text":"W: test \"network\"","color":"#abcdef"},{"full_text":"VOL: 42%"},{"full_text":"clock"}]'
"$bar" --once > "$work/frame.json"
jq -e '
    length == 6 and
    (.[0].full_text | test("^ .+ $")) and
    (.[1].full_text | startswith(" VPN: ")) and
    .[2].full_text == " W: test \"network\" " and
    .[2].color == "#abcdef" and
    (.[3].full_text | test("SSD: [0-9.]+/[0-9.]+ GiB \\| RAM: [0-9.]+/[0-9.]+ GiB")) and
    .[4].full_text == " VOL: 42% " and
    .[5].full_text == " clock " and
    all(.[]; .separator_block_width == 1)
' "$work/frame.json" > /dev/null
# Unexpected producer EOF must fail, but every frame must be valid and freed.
if MY_BAR_FRAMES=1000 "$bar" > "$work/stream" 2>"$work/error"; then
    echo 'FAIL: accepted unexpected producer EOF' >&2
    exit 1
fi
if grep -Eq 'AddressSanitizer|LeakSanitizer|runtime error:' "$work/error"; then
    cat "$work/error" >&2
    exit 1
fi
sed '1d' "$work/stream" > "$work/stream.json"
printf ']\n' >> "$work/stream.json"
jq -e 'length == 1000 and all(.[]; length == 6)' "$work/stream.json" > /dev/null
for MY_BAR_FRAME in 'not-json' '[{}]' '[null]' '[{"full_text":3}]'; do
    export MY_BAR_FRAME
    if "$bar" --once > /dev/null 2>"$work/error"; then
        echo "FAIL: accepted malformed status frame: $MY_BAR_FRAME" >&2
        exit 1
    fi
    if grep -Eq 'AddressSanitizer|LeakSanitizer|runtime error:' "$work/error"; then
        cat "$work/error" >&2
        exit 1
    fi
done
MY_BAR_FRAME='[]' "$bar" --once > "$work/empty.json"
jq -e 'length == 3' "$work/empty.json" > /dev/null
if "$bar" --unknown > /dev/null 2>"$work/error"; then
    echo 'FAIL: accepted unknown argument' >&2
    exit 1
fi
if grep -Eq 'AddressSanitizer|LeakSanitizer|runtime error:' "$work/error"; then
    cat "$work/error" >&2
    exit 1
fi
echo 'PASS: native modules, JSON escaping, existing blocks, malformed input, and CLI'
