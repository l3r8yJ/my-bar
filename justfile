flags := "-std=c17 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -Werror -Wformat=2 -Wshadow -Wconversion -Wstrict-prototypes -Wmissing-prototypes"
packages := "x11 libsystemd json-c"

default: check

clean:
    rm -rf -- build

build:
    mkdir -p build
    cc {{flags}} -O2 $(pkg-config --cflags {{packages}}) src/*.c -o build/my-bar $(pkg-config --libs {{packages}})

test: build
    cc {{flags}} -O2 $(pkg-config --cflags x11 json-c) tests/keyboard.c src/keyboard.c -o build/test-keyboard $(pkg-config --libs json-c)
    cc {{flags}} -O2 $(pkg-config --cflags json-c) tests/metrics.c src/metrics.c -o build/test-metrics $(pkg-config --libs json-c)
    cc {{flags}} -O2 $(pkg-config --cflags libsystemd json-c) tests/vpn.c src/vpn.c -o build/test-vpn $(pkg-config --libs libsystemd json-c)
    ./build/test-keyboard
    ./build/test-metrics
    dbus-run-session -- ./build/test-vpn
    sh tests/check.sh

format:
    clang-format -i src/*.c src/*.h tests/*.c

format-check:
    clang-format --dry-run --Werror src/*.c src/*.h tests/*.c

lint:
    clang-tidy src/*.c tests/*.c -- {{flags}} $(pkg-config --cflags {{packages}})

analyze:
    mkdir -p build
    for source in src/*.c tests/*.c; do cc {{flags}} -fanalyzer -c $(pkg-config --cflags {{packages}}) "$source" -o "build/analyze-$(basename "$source").o" || exit; done

sanitize:
    mkdir -p build
    clang {{flags}} -g -O1 -fno-omit-frame-pointer -fsanitize=address,undefined $(pkg-config --cflags {{packages}}) src/*.c -o build/my-bar-sanitize $(pkg-config --libs {{packages}})
    clang {{flags}} -g -O1 -fno-omit-frame-pointer -fsanitize=address,undefined $(pkg-config --cflags x11 json-c) tests/keyboard.c src/keyboard.c -o build/test-keyboard-sanitize $(pkg-config --libs json-c)
    clang {{flags}} -g -O1 -fno-omit-frame-pointer -fsanitize=address,undefined $(pkg-config --cflags json-c) tests/metrics.c src/metrics.c -o build/test-metrics-sanitize $(pkg-config --libs json-c)
    clang {{flags}} -g -O1 -fno-omit-frame-pointer -fsanitize=address,undefined $(pkg-config --cflags libsystemd json-c) tests/vpn.c src/vpn.c -o build/test-vpn-sanitize $(pkg-config --libs libsystemd json-c)
    ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 ./build/test-keyboard-sanitize
    ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 ./build/test-metrics-sanitize
    ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 dbus-run-session -- ./build/test-vpn-sanitize
    ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 MY_BAR_BIN=./build/my-bar-sanitize sh tests/check.sh

check: format-check lint analyze test sanitize

run: build
    ./build/my-bar

install: check
    install -Dm755 build/my-bar "$HOME/.local/bin/my-bar"
