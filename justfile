tools := env('MY_BAR_TOOLS', justfile_directory() + '/.tools')
compiler := tools + '/ldc/bin/ldc2'
dub := tools + '/ldc/bin/dub'
formatter := tools + '/dfmt'
scanner := tools + '/dscanner'

export DUB_HOME := justfile_directory() + '/build/dub'

default: check

setup:
    sh scripts/setup-tools.sh '{{tools}}'

clean:
    rm -rf -- build

build: setup
    '{{dub}}' build --compiler='{{compiler}}' --config=application --build=release

test: build
    '{{dub}}' test --compiler='{{compiler}}' --config=unittest
    '{{dub}}' build --compiler='{{compiler}}' --config=keyboard-fixture --build=debug
    MY_BAR_KEYBOARD_TEST=1 LD_PRELOAD="$PWD/build/libxkb-fixture.so" ./build/test-all
    '{{dub}}' build --compiler='{{compiler}}' --config=vpn-fixture --build=debug
    VPN_TEST_BIN=./build/test-all VPN_SERVICE_BIN=./build/vpn-service sh tests/vpn-integration.sh
    sh tests/check.sh
    sh tests/process.sh

format: setup
    find src tests -name '*.d' -exec '{{formatter}}' --inplace {} +

format-check: setup
    sh scripts/check-format.sh '{{formatter}}' src tests

lint: setup
    '{{compiler}}' -w -de -c -o- -Isrc $(find src tests -name '*.d')
    '{{dub}}' build --compiler='{{compiler}}' --config=application --build=syntax
    '{{scanner}}' --styleCheck --config=dscanner.ini -Isrc src tests
    sh scripts/check-policy.sh '{{scanner}}' src tests
    sh scripts/check-tools.sh '{{tools}}'

sanitize: setup
    ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 '{{dub}}' test --compiler='{{compiler}}' --config=unittest --build=unittest-sanitize
    '{{dub}}' build --compiler='{{compiler}}' --config=keyboard-fixture --build=debug
    ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 MY_BAR_KEYBOARD_TEST=1 LD_PRELOAD="$PWD/build/libxkb-fixture.so" ./build/test-all
    '{{dub}}' build --compiler='{{compiler}}' --config=vpn-fixture --build=sanitize
    ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 VPN_TEST_BIN=./build/test-all VPN_SERVICE_BIN=./build/vpn-service sh tests/vpn-integration.sh
    '{{dub}}' build --compiler='{{compiler}}' --config=application --build=sanitize
    ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 MY_BAR_BIN=./build/my-bar sh tests/check.sh
    ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 MY_BAR_BIN=./build/my-bar sh tests/process.sh
    '{{dub}}' build --compiler='{{compiler}}' --config=application --build=release
check: format-check lint test sanitize

install: check
    install -Dm755 build/my-bar "$HOME/.local/bin/my-bar"

run: build
    ./build/my-bar

[positional-arguments]
package version: build
    sh scripts/package.sh "$1"

release-check:
    shellcheck -x scripts/*.sh tests/*.sh
    sh tests/release.sh
    sh tests/publish.sh
