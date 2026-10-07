# my-bar

[![CI](https://github.com/l3r8yJ/my-bar/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/l3r8yJ/my-bar/actions/workflows/ci.yml)

Native C status producer for i3bar. Keyboard layout, active NetworkManager VPNs,
SSD usage and RAM usage live in separate modules. The executable starts the native
`i3status` process for Wi-Fi, volume and the clock, then adds its own blocks to the
i3bar JSON stream. No Python or shell commands run on each refresh.

## Build and use

```sh
git clone https://github.com/l3r8yJ/my-bar.git
cd my-bar
```

Requires a C compiler, `pkg-config`, `just`, X11, libnm, json-c and i3status.
Checks additionally use `jq`, GCC, Clang, clang-tidy and clang-format.
On Arch the development headers ship with `libx11`,
`libnm` and `json-c`.

```sh
just build                  # build/my-bar
just check                  # formatting, lint, both analyzers, tests, sanitizers
just format                 # automatically format all C sources and headers
just run                    # stream i3bar JSON
just install                # check and install ~/.local/bin/my-bar
./build/my-bar --once       # one JSON array, useful for diagnostics
```

Set your i3 bar configuration to:

```i3
bar {
    status_command ~/.local/bin/my-bar
}
```

Keep your other existing bar settings. Restart i3 in place (`i3-msg restart`) to
restart the status process. `i3status` uses its standard configuration lookup;
use `~/.config/i3status/config`, `output_format = "i3bar"` and
`interval = 1`. That interval controls keyboard and other indicator refreshes.

`keyboard.c` reads the active group and its names directly from the XKB keyboard
map, displaying English as EN, Russian as RU, and other layouts by name. The root
window's `_XKB_RULES_NAMES` property can be stale and is deliberately not used.
It requires the desktop's DISPLAY
and XAUTHORITY environment; without an X display it shows `?`.
`vpn.c` uses libnm and reports VPN, WireGuard and tun connections; missing
NetworkManager reports `unavailable`. `metrics.c` reads `/proc/meminfo` and
`statvfs("/")`; missing values show `?`.

The program owns and terminates its i3status child. It exits on malformed status
frames or unexpected child EOF. It does not implement clickable blocks; the
existing status configuration only displays information.

## Strict quality checks

Every enabled compiler warning is an error (`-Werror`) in release builds, tests,
static analysis and sanitizer builds. clang-tidy uses `WarningsAsErrors: '*'`;
format drift fails `clang-format --dry-run --Werror`. `just install` requires the
entire check suite to pass. There are no sanitizer suppressions.

| Recipe | Tool and purpose |
| --- | --- |
| `just format` / `just format-check` | [clang-format](https://clang.llvm.org/docs/ClangFormat.html): automatic formatting and verification |
| `just lint` | [clang-tidy](https://clang.llvm.org/extra/clang-tidy/): bugprone, CERT, portability and performance checks, plus Clang Static Analyzer |
| `just analyze` | [GCC `-fanalyzer`](https://gcc.gnu.org/onlinedocs/gcc/Static-Analyzer-Options.html): an independent analyzer, including resource ownership |
| `just test` | Layout regressions, numeric parsing, escaped JSON, invalid input, 1,000-frame stream and CLI checks |
| `just sanitize` | [AddressSanitizer](https://clang.llvm.org/docs/AddressSanitizer.html), [LeakSanitizer](https://clang.llvm.org/docs/LeakSanitizer.html) and [UBSan](https://clang.llvm.org/docs/UndefinedBehaviorSanitizer.html): memory errors, leaks and undefined behavior on tested paths |

The CI workflow installs these tools in an Arch Linux container. clang-tidy also runs Clang Static Analyzer,
so a separate scan-build pass would duplicate that analysis. GCC supplies a second
independent analysis. Sanitized executables stay in `build/`; installation uses the
optimized executable without sanitizer runtime overhead.

Two targeted lint exceptions are documented in the source/config: glibc lacks
Annex K's optional `_s` APIs, and the X11 test double must retain X11's parameter
order. Diagnostic output and fixed-size display formatting explicitly discard
return values where no recovery is needed; data parsing and stream failures are
checked. Passing these checks does not prove that every possible execution is
free of leaks. LeakSanitizer needs a normal process environment; it can fail under
ptrace-based sandboxes. Do not disable leak detection to bypass that failure.
