tools := env('MY_BAR_TOOLS', justfile_directory() + '/.tools')
c3 := tools + '/c3/c3c'
formatter := tools + '/c3fmt'
flags := '--output-dir . --build-dir build --validation=strict --warn-deadcode=error --warn-recursivecontracts=error --warn-methodvisibility=error --warn-methodsnotresolved=error --warn-deprecation=error --warn-builtin=error --safe=yes --x86cpu=baseline --stack-protector=strong'
link_flags := '-l X11 -l systemd -z "-z relro" -z "-z now"'
release_flags := '--optlevel=more --optsize=small --single-module=yes -g0'
sources := `find src -name '*.c3' ! -name '*_test.c3' ! -path '*/fixture/*' | sort | tr '\n' ' '`
test_sources := `find src -name '*.c3' ! -path '*/fixture/*' | sort | tr '\n' ' '`

default: check

setup:
    sh scripts/setup-tools.sh '{{tools}}'

clean:
    rm -rf -- build

build: setup
    mkdir -p build
    '{{c3}}' compile {{sources}} {{flags}} {{release_flags}} {{link_flags}} -o build/my-bar

test: build
    '{{c3}}' compile-test {{test_sources}} {{flags}} {{link_flags}} --suppress-run -o build/test-all
    ./build/test-all
    '{{c3}}' dynamic-lib src/keyboard/fixture/fixture.c3 src/bindings/xkb.c3 {{flags}} --no-entry --no-headers -o build/xkb-fixture
    MY_BAR_KEYBOARD_TEST=1 LD_PRELOAD="$PWD/build/xkb-fixture.so" ./build/test-all
    '{{c3}}' compile tests/vpn-service/main.c3 {{flags}} -l systemd -o build/vpn-service
    VPN_TEST_BIN=./build/test-all VPN_SERVICE_BIN=./build/vpn-service sh tests/vpn-integration.sh
    sh tests/check.sh
    sh tests/process.sh

format: setup
    find src tests/vpn-service -name '*.c3' -exec '{{formatter}}' -i {} +

format-check: setup
    find src tests/vpn-service -name '*.c3' -exec '{{formatter}}' --check {} +

lint: setup
    '{{c3}}' compile-only {{sources}} {{flags}} --no-obj
    sh scripts/check-tools.sh '{{tools}}' {{flags}}

sanitize: setup
    mkdir -p build
    '{{c3}}' compile {{sources}} {{flags}} {{link_flags}} -g --sanitize=address -o build/my-bar-sanitize
    '{{c3}}' compile-test {{test_sources}} {{flags}} {{link_flags}} -g --sanitize=address --suppress-run -o build/test-all-sanitize
    ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 ./build/test-all-sanitize
    '{{c3}}' compile-only src/keyboard/fixture/fixture.c3 src/bindings/xkb.c3 {{flags}} --no-entry -g --sanitize=address --reloc=pic --single-module=yes --obj-out build/xkb-sanitize
    cc -shared build/xkb-sanitize/bar.fixture.o -fsanitize=address -o build/xkb-fixture-sanitize.so
    ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 MY_BAR_KEYBOARD_TEST=1 LD_PRELOAD="$(cc -print-file-name=libasan.so):$PWD/build/xkb-fixture-sanitize.so" ./build/test-all-sanitize
    '{{c3}}' compile tests/vpn-service/main.c3 {{flags}} -l systemd -g --sanitize=address -o build/vpn-service-sanitize
    ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 VPN_TEST_BIN=./build/test-all-sanitize VPN_SERVICE_BIN=./build/vpn-service-sanitize sh tests/vpn-integration.sh
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
