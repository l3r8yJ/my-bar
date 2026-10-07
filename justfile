tools := env('MY_BAR_TOOLS', justfile_directory() + '/.tools')
odin := tools + '/odin/odin'
formatter := tools + '/odinfmt'
flags := '-vet -strict-style -vet-tabs -vet-using-param -disallow-do -warnings-as-errors'
test_flags := '-define:ODIN_TEST_TRACK_MEMORY=true -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true'
release_flags := '-o:size -microarch:x86-64 -stack-protector:strong -extra-linker-flags:"-Wl,-z,relro,-z,now"'

default: check

setup:
    sh scripts/setup-tools.sh '{{tools}}'

clean:
    rm -rf -- build

build: setup
    mkdir -p build
    '{{odin}}' build src {{flags}} {{release_flags}} -out:build/my-bar

test: build
    for package in src src/metrics src/stream; do '{{odin}}' test "$package" {{flags}} {{test_flags}} -out:build/test-$(basename "$package") || exit; done
    '{{odin}}' build src/keyboard/fixture -build-mode:dll {{flags}} -out:build/xkb-fixture.so
    '{{odin}}' build src/keyboard -build-mode:test {{flags}} {{test_flags}} -out:build/test-keyboard
    MY_BAR_KEYBOARD_TEST=1 LD_PRELOAD="$PWD/build/xkb-fixture.so" ./build/test-keyboard
    '{{odin}}' build src/vpn -build-mode:test {{flags}} {{test_flags}} -out:build/test-vpn
    '{{odin}}' build tests/vpn-service {{flags}} -out:build/vpn-service
    VPN_TEST_BIN=./build/test-vpn VPN_SERVICE_BIN=./build/vpn-service sh tests/vpn-integration.sh
    sh tests/check.sh
    sh tests/process.sh

format: setup
    '{{formatter}}' src -w
    '{{formatter}}' tests/vpn-service -w

format-check: setup
    sh scripts/check-format.sh '{{formatter}}' src tests/vpn-service

lint: setup
    '{{odin}}' check src {{flags}} -vet-unused-procedures -vet-packages:main,keyboard,vpn,metrics,errors,status,bindings,stream
    sh scripts/check-tools.sh '{{tools}}'

sanitize: setup
    mkdir -p build
    '{{odin}}' build src {{flags}} -debug -sanitize:address -out:build/my-bar-sanitize
    for package in src src/metrics src/stream; do ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 '{{odin}}' test "$package" {{flags}} {{test_flags}} -debug -sanitize:address -out:build/test-$(basename "$package")-sanitize || exit; done
    '{{odin}}' build src/keyboard/fixture -build-mode:dll {{flags}} -debug -sanitize:address -out:build/xkb-fixture-sanitize.so
    '{{odin}}' build src/keyboard -build-mode:test {{flags}} {{test_flags}} -debug -sanitize:address -out:build/test-keyboard-sanitize
    ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 MY_BAR_KEYBOARD_TEST=1 LD_PRELOAD="$PWD/build/xkb-fixture-sanitize.so" ./build/test-keyboard-sanitize
    '{{odin}}' build src/vpn -build-mode:test {{flags}} {{test_flags}} -debug -sanitize:address -out:build/test-vpn-sanitize
    '{{odin}}' build tests/vpn-service {{flags}} -debug -sanitize:address -out:build/vpn-service-sanitize
    ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 VPN_TEST_BIN=./build/test-vpn-sanitize VPN_SERVICE_BIN=./build/vpn-service-sanitize sh tests/vpn-integration.sh
    ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 MY_BAR_BIN=./build/my-bar-sanitize sh tests/check.sh
    ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 MY_BAR_BIN=./build/my-bar-sanitize sh tests/process.sh

check: format-check lint test sanitize

run: build
    ./build/my-bar

install: build
    install -Dm755 build/my-bar "$HOME/.local/bin/my-bar"

[positional-arguments]
package version: check
    sh scripts/package.sh "$1"

release-check:
    shellcheck -x scripts/*.sh tests/*.sh
    sh tests/release.sh
    sh tests/publish.sh
