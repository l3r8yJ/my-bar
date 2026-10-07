tools := env('MY_BAR_TOOLS', '')
compiler := if tools == '' { 'ldc2' } else { tools + '/ldc/bin/ldc2' }
dub := if tools == '' { 'dub' } else { tools + '/ldc/bin/dub' }
formatter := if tools == '' { 'dfmt' } else { tools + '/dfmt' }
scanner := if tools == '' { 'dscanner' } else { tools + '/dscanner' }

export DUB_HOME := justfile_directory() + '/build/dub'

default: check

setup:
    @sh scripts/check-deps.sh all '{{compiler}}' '{{dub}}' '{{formatter}}' '{{scanner}}'

clean:
    rm -rf -- build

build:
    @sh scripts/check-deps.sh build '{{compiler}}' '{{dub}}' '{{formatter}}' '{{scanner}}'
    '{{dub}}' build --skip-registry=all --compiler='{{compiler}}' --config=application --build=release

test: build
    sh tests/dependencies.sh
    @sh scripts/check-deps.sh test '{{compiler}}' '{{dub}}' '{{formatter}}' '{{scanner}}'
    '{{dub}}' test --skip-registry=all --compiler='{{compiler}}' --config=unittest
    '{{dub}}' build --skip-registry=all --compiler='{{compiler}}' --config=keyboard-fixture --build=debug
    MY_BAR_KEYBOARD_TEST=1 LD_PRELOAD="$PWD/build/libxkb-fixture.so" ./build/test-all
    '{{dub}}' build --skip-registry=all --compiler='{{compiler}}' --config=vpn-fixture --build=debug
    VPN_TEST_BIN=./build/test-all VPN_SERVICE_BIN=./build/vpn-service sh tests/vpn-integration.sh
    sh tests/check.sh
    sh tests/process.sh

format:
    @sh scripts/check-deps.sh format '{{compiler}}' '{{dub}}' '{{formatter}}' '{{scanner}}'
    find src tests -name '*.d' -exec '{{formatter}}' --inplace {} +

format-check:
    @sh scripts/check-deps.sh format '{{compiler}}' '{{dub}}' '{{formatter}}' '{{scanner}}'
    sh scripts/check-format.sh '{{formatter}}' src tests

lint:
    @sh scripts/check-deps.sh lint '{{compiler}}' '{{dub}}' '{{formatter}}' '{{scanner}}'
    '{{compiler}}' -w -de -c -o- -Isrc $(find src tests -name '*.d')
    '{{dub}}' build --skip-registry=all --compiler='{{compiler}}' --config=application --build=syntax
    '{{scanner}}' --styleCheck --config=dscanner.ini -Isrc src tests
    sh scripts/check-policy.sh '{{scanner}}' src tests
    sh scripts/check-tools.sh '{{compiler}}' '{{formatter}}' '{{scanner}}'

sanitize:
    @sh scripts/check-deps.sh test '{{compiler}}' '{{dub}}' '{{formatter}}' '{{scanner}}'
    ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 '{{dub}}' test --skip-registry=all --compiler='{{compiler}}' --config=unittest --build=unittest-sanitize
    '{{dub}}' build --skip-registry=all --compiler='{{compiler}}' --config=keyboard-fixture --build=debug
    ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 MY_BAR_KEYBOARD_TEST=1 LD_PRELOAD="$(ldd build/test-all | awk '/libasan\.so|libclang_rt\.asan/ { print $3 }'):$PWD/build/libxkb-fixture.so" ./build/test-all
    '{{dub}}' build --skip-registry=all --compiler='{{compiler}}' --config=vpn-fixture --build=sanitize
    ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 VPN_TEST_BIN=./build/test-all VPN_SERVICE_BIN=./build/vpn-service sh tests/vpn-integration.sh
    '{{dub}}' build --skip-registry=all --compiler='{{compiler}}' --config=application --build=sanitize
    ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 MY_BAR_BIN=./build/my-bar sh tests/check.sh
    ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 MY_BAR_BIN=./build/my-bar sh tests/process.sh
    '{{dub}}' build --skip-registry=all --compiler='{{compiler}}' --config=application --build=release
check: format-check lint test sanitize

install: check
    install -Dm755 build/my-bar "$HOME/.local/bin/my-bar"

run: build
    ./build/my-bar

[positional-arguments]
package version: build
    @sh scripts/check-deps.sh package '{{compiler}}' '{{dub}}' '{{formatter}}' '{{scanner}}'
    sh scripts/package.sh "$1"

release-check:
    @sh scripts/check-deps.sh release '{{compiler}}' '{{dub}}' '{{formatter}}' '{{scanner}}'
    shellcheck -x scripts/*.sh tests/*.sh
    sh tests/release.sh
    sh tests/publish.sh
