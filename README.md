# my-bar

[![CI](https://github.com/l3r8yJ/my-bar/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/l3r8yJ/my-bar/actions/workflows/ci.yml)
[![PDD status](https://www.0pdd.com/svg?name=l3r8yJ/my-bar)](https://www.0pdd.com/p?name=l3r8yJ/my-bar)

Native C status producer for i3bar. Keyboard layout, active NetworkManager VPNs,
SSD usage and RAM usage live in separate modules. The executable starts the native
`i3status` process for Wi-Fi, volume and the clock, then adds its own blocks to the
i3bar JSON stream. No Python or shell commands run on each refresh.

## Build and use

```sh
git clone https://github.com/l3r8yJ/my-bar.git
cd my-bar
```

Requires a C compiler, `pkg-config`, `just`, X11, libsystemd, json-c and i3status.
Checks additionally use `jq`, GCC, Clang, clang-tidy, clang-format and `dbus-run-session`.
On Arch the development headers ship with `libx11`,
`systemd-libs` and `json-c`. Install `dbus` for the isolated VPN tests.

```sh
just build                  # build/my-bar
just clean                  # remove generated build files
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
`vpn.c` reads NetworkManager's D-Bus properties through libsystemd's sd-bus API,
without libnm/GLib or background threads. It polls active VPN, WireGuard and tun
connections each refresh; each D-Bus method call has a 100 ms timeout. Missing
NetworkManager or failed property reads report `unavailable`. `metrics.c` reads `/proc/meminfo` and
`statvfs("/")`; missing values show `?`.

The program owns and terminates its i3status child. It exits on malformed status
frames or unexpected child EOF. It does not implement clickable blocks; the
existing status configuration only displays information.

## Strict quality checks

Every enabled compiler warning is an error (`-Werror`) in release builds, tests,
static analysis and sanitizer builds. clang-tidy uses `WarningsAsErrors: '*'`;
format drift fails `clang-format --dry-run --Werror`. `just install` requires the
entire check suite to pass. There are no sanitizer suppressions.

`goto` is forbidden by `lint/no-goto.h`, force-included by every build and lint
command. GCC and Clang reject the token even in macros; comments and strings are
unaffected. `just lint` verifies this policy with rejected C fixtures.

Recoverable failures are returned as values. `src/error/result.h` defines
`StringResult` and `MUST_USE`. Its `error` field is negative on failure and zero on
success; `value` is an optional caller-owned string that the caller frees. This
represents `Result<Option<String>, Error>` without Rust ownership enforcement.
The VPN lookup returns this shared type, while its NetworkManager logic stays in
`vpn.c`. Early returns replace cleanup jumps; ignoring a `MUST_USE` result fails
the warning-fatal build.

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

Targeted lint exceptions are documented in the source/config: glibc lacks
Annex K's optional `_s` APIs, and X11/sd-bus callbacks must retain their ABI parameter
order. Diagnostic output and fixed-size display formatting explicitly discard
return values where no recovery is needed; data parsing and stream failures are
checked. Passing these checks does not prove that every possible execution is
free of leaks. LeakSanitizer needs a normal process environment; it can fail under
ptrace-based sandboxes. Do not disable leak detection to bypass that failure.

## Repository bots

[Rultor](https://doc.rultor.com/basics.html) runs `just check` in
`debian:trixie-slim`, installing only required build dependencies before merging.
A repository collaborator can request a merge
by commenting `@rultor merge` on a pull request. `.rultor.yml` defines the build;
it does not configure deployment or releases.

[0pdd](https://github.com/yegor256/0pdd#how-to-start) scans TODO puzzles in `src/`
and `tests/` on pushes to `master`, creates issues labelled `pdd`, and closes them
when the puzzles are removed. `.0pdd.yml` limits each scan to ten new issues;
`.pdd` defines the source paths. Both bots need repository collaborator access,
and 0pdd needs a push webhook to `https://www.0pdd.com/hook/github` with JSON
content. Its configuration becomes active once these files are merged to `master`.

The separate **Puzzles** GitHub Actions workflow validates puzzles on pull
requests and pushes using the PDD action used by 0pdd itself. It has read-only
repository access; the hosted 0pdd bot handles issue creation and closure.

To record real follow-up work in C, use a comment such as
`/* @todo #42:30min Describe the concrete remaining work here. */`, replacing 42
with the related issue number. No placeholder puzzles are included in the code.

## Releases

Request a stable release in a GitHub issue after the release configuration is
merged into master:

```text
@rultor release, tag is `v0.1.0`
```

Use `vMAJOR.MINOR.PATCH` without leading zeroes. Rultor validates the version,
runs the checks on the local worker, and pushes the tag only on success.
The **Package checks** workflow validates pull requests and manual runs. The
tag-only **Release** workflow calls the same checks for the tagged source before
publishing. Packaging uses an Arch Linux x86-64 container, runs all checks,
strips a copy of the executable, builds
an Arch package as an unprivileged user, and rejects namcap warnings and errors.
The sole namcap exception is `dependency-not-needed i3status`: the program
launches i3status at runtime, which ELF dependency analysis cannot detect.
The runtime check verifies that pacman installs i3status alongside my-bar.
A clean runtime container installs the package with pacman and tests the installed
executable. Pull requests and manual workflow runs check packaging without
publishing.

For tags pushed by `rultor`, the workflow publishes a public GitHub Release with:

- `my-bar-bin-X.Y.Z-1-x86_64.pkg.tar.zst`: ready-to-install Arch package.
- `my-bar-vX.Y.Z-linux-x86_64-arch.tar.gz`: prebuilt executable, MIT license,
  README and version/commit metadata.
- `PKGBUILD` and `.SRCINFO`: recipe for installing the prebuilt binary.
- `SHA256SUMS`: checksums for all four assets; checksums are not signatures.

Download the assets from [Releases](https://github.com/l3r8yJ/my-bar/releases)
into an empty directory. For example, for version 0.1.0:

```sh
sha256sum --check SHA256SUMS
sudo pacman -U ./my-bar-bin-0.1.0-1-x86_64.pkg.tar.zst
```

Pacman installs the declared runtime dependencies. Configure i3 to run `my-bar`
as its status command. The binary targets current Arch Linux x86-64; other
distributions and architectures are not supported by this artifact. Keyboard
status needs an X11 session; VPN status uses NetworkManager through D-Bus.

Alternatively, download `PKGBUILD` to an empty directory, review it, and run
`paru -Bi .` or `makepkg -si` as your regular user. The recipe downloads the
prebuilt binary from GitHub and verifies its checksum; it does not compile C.
This does not require an AUR account. The project is not yet listed in the AUR,
so `paru -S my-bar-bin` and automatic AUR updates are not available. Once AUR
registration is available, the release's `PKGBUILD` and `.SRCINFO` can be pushed
to `ssh://aur@aur.archlinux.org/my-bar-bin.git` by its maintainer.

For local packaging:

```sh
docker build -f release/Dockerfile -t my-bar-release \
  --build-arg BUILDER_UID="$(id -u)" --build-arg BUILDER_GID="$(id -g)" .
docker run --rm -v "$PWD:/work" \
  -e SOURCE_DATE_EPOCH="$(git show -s --format=%ct HEAD)" \
  -e RELEASE_COMMIT="$(git rev-parse HEAD)" -e RELEASE_VERSION=v0.1.0 \
  my-bar-release sh -ec 'just check; just package "$RELEASE_VERSION"; just release-check'
```

`just release-check` validates the package selected by `RELEASE_VERSION`
(default `v0.0.0`), including repeatable binary archive packaging. Artifacts live
under `build/release/` and are removed by `just clean`. Container base images are
pinned, but Arch packages are updated when building the image; release builds
are not guaranteed reproducible across different package repository snapshots.

Rultor tag creation and GitHub publication are separate steps. A failed upload
leaves a draft release; rerun the failed workflow to finish it. Published assets
are never replaced automatically. No personal access token or worker secret is
needed for publication, and downloading public release assets needs no account.
